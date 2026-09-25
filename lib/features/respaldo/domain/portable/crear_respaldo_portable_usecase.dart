import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../../core/security/aes_gcm_hkdf_streaming.dart';
import '../../../../core/security/credential_cipher.dart';
import '../manifest_respaldo.dart';
import '../usecases/crear_respaldo_usecase.dart';
import 'configuracion_recuperacion.dart';
import 'contenedor_portable.dart';
import 'payload_portable.dart';
import 'sobre_portable.dart';
import 'verificar_respaldo_portable_usecase.dart';

sealed class ResultadoCrearPortable {}

class PortableCreado extends ResultadoCrearPortable {
  PortableCreado({required this.ruta, required this.packageId, required this.bytes});
  final String ruta;
  final String packageId;
  final int bytes;
}

/// No hay configuración de recuperación: no se puede envolver nada.
class PortableSinConfiguracion extends ResultadoCrearPortable {}

/// La frase no abre la clave maestra del conjunto. Se responde igual que
/// ante un paquete manipulado: sin decir qué comprobación falló.
class PortableCredencialIncorrecta extends ResultadoCrearPortable {}

/// **Este equipo no tiene la clave AES de RISEG ONE.**
///
/// Se falla en vez de crearla. Un portable con una clave recién
/// inventada parecería perfectamente válido y sería incapaz de abrir un
/// solo secreto de los que acompaña — y eso no se descubriría hasta el
/// día de la emergencia, en otra computadora.
class PortableSinClaveDeCifrado extends ResultadoCrearPortable {}

/// El respaldo interno no pudo producirse (la base no pasó sus PRAGMAs,
/// el destino no está disponible…).
class PortableRespaldoInternoFallido extends ResultadoCrearPortable {
  PortableRespaldoInternoFallido(this.interno);
  final ResultadoCrearRespaldo interno;
}

/// El paquete se escribió pero **no superó su propia verificación**. No
/// se entrega: un respaldo que no se puede abrir no es un respaldo, y
/// descubrirlo el día que hace falta sería lo peor que podría pasar.
class PortableNoSuperaAutoverificacion extends ResultadoCrearPortable {
  PortableNoSuperaAutoverificacion(this.motivo);
  final String motivo;
}

class PortableDestinoNoDisponible extends ResultadoCrearPortable {
  PortableDestinoNoDisponible(this.detalle);
  final String detalle;
}

class PortableErrorInesperado extends ResultadoCrearPortable {
  PortableErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Crea un `.risegbkp`: el respaldo v2 de la Etapa 4B, más la clave AES
/// de este equipo, dentro de un contenedor cifrado y autenticado que
/// puede abrirse en otra computadora con la frase **o** con la clave de
/// recuperación (Etapa 4D).
///
/// El orden de las operaciones es deliberado y no se puede reordenar sin
/// perder garantías:
///
///  1. la frase se comprueba **antes** de trabajar, abriendo la MWK;
///  2. la clave AES se lee **sin crearla**, y si falta se aborta;
///  3. el paquete se escribe a `.parcial`;
///  4. se **autoverifica** con el mismo camino que usará una
///     restauración;
///  5. sólo entonces se renombra al nombre definitivo.
///
/// Si algo falla, no queda ningún archivo con nombre de respaldo bueno.
class CrearRespaldoPortableUseCase {
  CrearRespaldoPortableUseCase({
    required String databaseFile,
    required String attachmentsDir,
    required String stagingDir,
    required String appVersion,
    required CredentialCipher cipher,
    CrearRespaldoUseCase? crearRespaldoV2,
    VerificarRespaldoPortableUseCase? verificador,
    SobrePortable? sobre,
    Random? aleatorio,
    DateTime Function()? ahora,
  }) : _stagingDir = stagingDir,
       _appVersion = appVersion,
       _cipher = cipher,
       _crearRespaldoV2 =
           crearRespaldoV2 ?? CrearRespaldoUseCase(databaseFile: databaseFile, attachmentsDir: attachmentsDir),
       _verificador = verificador ?? VerificarRespaldoPortableUseCase(stagingDir: stagingDir),
       _sobre = sobre ?? SobrePortable(),
       _aleatorio = aleatorio ?? Random.secure(),
       _ahora = ahora ?? DateTime.now;

  final String _stagingDir;
  final String _appVersion;
  final CredentialCipher _cipher;
  final CrearRespaldoUseCase _crearRespaldoV2;
  final VerificarRespaldoPortableUseCase _verificador;
  final SobrePortable _sobre;
  final Random _aleatorio;
  final DateTime Function() _ahora;

  static const sufijoParcial = '.parcial';

  Future<ResultadoCrearPortable> ejecutar({
    required String destino,
    required String frase,
    required ConfiguracionRecuperacion configuracion,
    required int appSchemaVersion,
  }) async {
    final parcial = File('$destino$sufijoParcial');
    final staging = Directory(p.join(_stagingDir, 'portable_${_hexAleatorio(8)}'));

    try {
      // 1. La frase primero. Si no abre la MWK, no se toca nada más: es
      //    barato (48 bytes) y evita construir un respaldo para tirarlo.
      final mwk = configuracion.abrirMwkConFrase(frase: frase, sobre: _sobre);
      if (mwk == null) return PortableCredencialIncorrecta();

      // 2. La clave AES, SIN crearla.
      final Uint8List claveAes;
      try {
        claveAes = await _cipher.obtenerClaveExistente();
      } on ClaveCifradoNoDisponible {
        return PortableSinClaveDeCifrado();
      }

      staging.createSync(recursive: true);

      // 3. El respaldo interno, con el motor de 4B sin modificar.
      final rutaV2 = p.join(staging.path, 'respaldo_v2.zip');
      final interno = await _crearRespaldoV2.ejecutar(destinoZip: rutaV2, tipo: TipoRespaldo.manual);
      if (interno is! RespaldoCreado) return PortableRespaldoInternoFallido(interno);

      // 4. El payload privado: respaldo v2 + registro de clave.
      final rutaPayload = p.join(staging.path, 'payload.bin');
      final creadoEn = _ahora();
      await PayloadPortable.construir(
        destino: File(rutaPayload),
        respaldoV2: File(rutaV2),
        clave: RegistroClaveAes(keyId: _hexAleatorio(16), clave: claveAes),
        backupSetId: configuracion.backupSetId,
        appVersion: _appVersion,
        createdAt: creadoEn,
      );

      // 5. R1 con el tamaño del payload ya calculado — se puede saber
      //    antes de cifrar, y el parser lo exige exacto.
      final textoPlanoBytes = await File(rutaPayload).length();
      final packageId = _hexAleatorio(16);
      final r1 = ConstructorZonaCabecera.construirR1(
        CabeceraPublica(
          packageId: packageId,
          backupSetId: configuracion.backupSetId,
          createdAt: creadoEn,
          appSchemaVersion: appSchemaVersion,
          appVersion: _appVersion,
          segmentSize: ContenedorPortable.segmentSizePorOmision,
          payloadBytes: ConstructorZonaCabecera.calcularPayloadBytes(
            textoPlanoBytes: textoPlanoBytes,
            segmentSize: ContenedorPortable.segmentSizePorOmision,
          ),
        ),
      );

      // 6. DEK propia de este paquete, envuelta bajo la MWK. Las
      //    envolturas de la MWK se copian tal cual de la configuración:
      //    la clave de recuperación no hace falta aquí.
      final prefijoAad = ContenedorPortable.prefijoAad(r1.zona);
      final dek = _sobre.generarDek();
      final dekWrap = _sobre.envolverDek(dek: dek, mwk: mwk, prefijoAad: prefijoAad);
      final zona = ConstructorZonaCabecera.completar(
        zonaConR1: r1.zona,
        dekWrapNonce: dekWrap.nonce,
        dekWrapCifrado: dekWrap.cifrado,
        envolturas: configuracion.envolturas,
      );

      // 7. Escritura: cabecera y payload cifrado por segmentos.
      try {
        if (parcial.existsSync()) await parcial.delete();
        parcial.parent.createSync(recursive: true);
        final salida = await parcial.open(mode: FileMode.write);
        try {
          await salida.writeFrom(zona);
          await AesGcmHkdfStreaming(ikm: dek, segmentSize: ContenedorPortable.segmentSizePorOmision).cifrarArchivoHacia(
            origen: File(rutaPayload),
            destino: salida,
            datosAsociados: prefijoAad,
            salt: _sobre.bytesAleatorios(AesGcmHkdfStreaming.longitudSalt),
            prefijoNonce: _sobre.bytesAleatorios(AesGcmHkdfStreaming.longitudPrefijoNonce),
          );
          await salida.flush();
        } finally {
          await salida.close();
        }
      } on FileSystemException catch (e) {
        await _borrarSiSePuede(parcial);
        return PortableDestinoNoDisponible(e.message);
      }

      // 8. Autoverificación por el mismo camino que una restauración.
      final verificacion = await _verificador.ejecutar(
        rutaPaquete: parcial.path,
        frase: frase,
        appSchemaVersionActual: appSchemaVersion,
      );
      if (verificacion is! PortableVerificado) {
        await _borrarSiSePuede(parcial);
        return PortableNoSuperaAutoverificacion(verificacion.runtimeType.toString());
      }

      // 9. Recién ahora el archivo recibe su nombre definitivo.
      try {
        final definitivo = File(destino);
        if (definitivo.existsSync()) await definitivo.delete();
        await parcial.rename(destino);
      } on FileSystemException catch (e) {
        await _borrarSiSePuede(parcial);
        return PortableDestinoNoDisponible(e.message);
      }

      return PortableCreado(ruta: destino, packageId: packageId, bytes: await File(destino).length());
    } catch (e) {
      await _borrarSiSePuede(parcial);
      return PortableErrorInesperado(e.toString());
    } finally {
      // El staging lleva la base y el respaldo en claro: se borra
      // siempre, incluso si algo lanzó.
      if (staging.existsSync()) {
        try {
          await staging.delete(recursive: true);
        } on FileSystemException {
          // Se reintentará al arrancar; ver la limpieza de huérfanos.
        }
      }
    }
  }

  String _hexAleatorio(int bytes) {
    return List<int>.generate(
      bytes,
      (_) => _aleatorio.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Si no se puede borrar (la unidad se desconectó), se deja: lleva
  /// `.parcial` en el nombre y no engaña a nadie.
  Future<void> _borrarSiSePuede(File archivo) async {
    try {
      if (archivo.existsSync()) await archivo.delete();
    } on FileSystemException {
      // Nada más que hacer desde aquí.
    }
  }
}
