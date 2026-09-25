import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../../core/security/aes_gcm_hkdf_streaming.dart';
import '../usecases/validar_paquete_respaldo_usecase.dart';
import 'clave_recuperacion.dart';
import 'configuracion_recuperacion.dart';
import 'contenedor_portable.dart';
import 'payload_portable.dart';
import 'sobre_portable.dart';

/// Lo que se puede saber de un `.risegbkp` **sin credencial** — la
/// "Información del respaldo" (Etapa 4D).
///
/// Deliberadamente **no** dice "íntegro" ni "verificado": leer una
/// cabecera pública no autentica nada, y presentarlo de otro modo
/// llevaría a confiar en un paquete que nadie ha comprobado.
class InformacionPortable {
  const InformacionPortable({
    required this.creadoEn,
    required this.appSchemaVersion,
    required this.appVersion,
    required this.bytes,
    required this.backupSetId,
    required this.tieneEnvolturaDeFrase,
    required this.tieneEnvolturaDeClaveRecuperacion,
  });

  final DateTime creadoEn;
  final int appSchemaVersion;
  final String appVersion;
  final int bytes;
  final String backupSetId;
  final bool tieneEnvolturaDeFrase;
  final bool tieneEnvolturaDeClaveRecuperacion;
}

sealed class ResultadoVerificarPortable {}

/// Todo comprobado: el contenedor, la credencial, el payload completo, el
/// respaldo v2 interno con su validador canónico, y el registro de clave.
class PortableVerificado extends ResultadoVerificarPortable {
  PortableVerificado({required this.informacion, required this.claveAes, required this.backupSetIdPayload});
  final InformacionPortable informacion;

  /// El registro de clave recuperado del payload. **Sólo existe en
  /// memoria**: no se escribe a ningún archivo lateral, no va al
  /// manifiesto público y no se registra en ningún log.
  final RegistroClaveAes claveAes;

  final String backupSetIdPayload;

  String get keyIdClaveAes => claveAes.keyId;
}

/// El archivo no tiene la forma de un contenedor RISEG.
class PortableEstructuraInvalida extends ResultadoVerificarPortable {
  PortableEstructuraInvalida(this.motivo);
  final MotivoContenedorInvalido motivo;
}

/// La credencial no abre el paquete, **o** el paquete fue modificado. Un
/// solo resultado para los dos casos: quien manipula un archivo no debe
/// saber qué comprobación falló.
class PortableCredencialIncorrectaOModificado extends ResultadoVerificarPortable {}

/// El contenido no autentica: dañado, truncado o manipulado.
class PortableContenidoDanado extends ResultadoVerificarPortable {
  PortableContenidoDanado(this.detalle);
  final String detalle;
}

/// El respaldo v2 de dentro no pasa el validador canónico de 4B.
class PortableRespaldoInternoInvalido extends ResultadoVerificarPortable {
  PortableRespaldoInternoInvalido(this.resultado);
  final ResultadoValidarPaqueteRespaldo resultado;
}

class PortableVerificarErrorInesperado extends ResultadoVerificarPortable {
  PortableVerificarErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Verifica un respaldo portable de arriba abajo (Etapa 4D).
///
/// Dos niveles, y la diferencia importa:
///
///  * [inspeccionar] lee la cabecera pública. No autentica nada y no
///    pide credencial. Sirve para poblar una lista y para rechazar un
///    paquete de una versión más nueva **antes** de pedir la frase.
///  * [ejecutar] recorre el paquete entero: abre la clave maestra, abre
///    la DEK, **autentica todos los segmentos**, extrae el payload y
///    pasa el respaldo interno por el validador canónico de 4B — que
///    comprueba SHA-256 de cada archivo, `integrity_check`,
///    `foreign_key_check` y los adjuntos. Sólo eso justifica decir
///    "verificado".
class VerificarRespaldoPortableUseCase {
  VerificarRespaldoPortableUseCase({
    required String stagingDir,
    ValidarPaqueteRespaldoUseCase? validador,
    SobrePortable? sobre,
  }) : _stagingDir = stagingDir,
       _validador = validador ?? ValidarPaqueteRespaldoUseCase(),
       _sobre = sobre ?? SobrePortable();

  final String _stagingDir;
  final ValidarPaqueteRespaldoUseCase _validador;
  final SobrePortable _sobre;

  /// Sin credencial. Lanza [ContenedorInvalido] si el archivo no es un
  /// contenedor RISEG utilizable.
  Future<InformacionPortable> inspeccionar({required String rutaPaquete}) async {
    final archivo = File(rutaPaquete);
    final leido = await _leerCabecera(archivo);
    return InformacionPortable(
      creadoEn: leido.cabecera.createdAt,
      appSchemaVersion: leido.cabecera.appSchemaVersion,
      appVersion: leido.cabecera.appVersion,
      bytes: await archivo.length(),
      backupSetId: leido.cabecera.backupSetId,
      tieneEnvolturaDeFrase: leido.tieneEnvolturaDeFrase,
      tieneEnvolturaDeClaveRecuperacion: leido.tieneEnvolturaDeClaveRecuperacion,
    );
  }

  /// Verificación completa. Se abre con [frase] **o** con
  /// [claveRecuperacionTexto]; basta una.
  ///
  /// Con [respaldoDestino] se conserva el respaldo v2 extraído —lo que
  /// necesita una restauración—; sin él, todo lo descifrado se borra al
  /// terminar y sólo queda el veredicto.
  Future<ResultadoVerificarPortable> ejecutar({
    required String rutaPaquete,
    required int appSchemaVersionActual,
    String? frase,
    String? claveRecuperacionTexto,
    File? respaldoDestino,
  }) async {
    final staging = Directory(p.join(_stagingDir, 'verificar_${DateTime.now().microsecondsSinceEpoch}'));
    try {
      final archivo = File(rutaPaquete);
      final ContenedorLeido leido;
      try {
        leido = await _leerCabecera(archivo);
      } on ContenedorInvalido catch (e) {
        return PortableEstructuraInvalida(e.motivo);
      }

      final prefijoAad = ContenedorPortable.prefijoAad(leido.zonaCabecera);
      final mwk = _abrirMwk(leido: leido, frase: frase, claveRecuperacionTexto: claveRecuperacionTexto);
      if (mwk == null) return PortableCredencialIncorrectaOModificado();

      final dek = _sobre.abrirDek(
        mwk: mwk,
        nonce: leido.dekWrapNonce,
        cifrado: leido.dekWrapCifrado,
        prefijoAad: prefijoAad,
      );
      if (dek == null) return PortableCredencialIncorrectaOModificado();

      staging.createSync(recursive: true);
      final payload = File(p.join(staging.path, 'payload.bin'));

      // Autenticar el payload COMPLETO, por segmentos, escribiéndolo al
      // staging para poder mirar dentro.
      final entrada = await archivo.open();
      final salida = await payload.open(mode: FileMode.write);
      try {
        await entrada.setPosition(ContenedorPortable.zonaCabecera);
        await AesGcmHkdfStreaming(ikm: dek, segmentSize: leido.cabecera.segmentSize).descifrarArchivoHacia(
          origen: entrada,
          payloadBytes: leido.cabecera.payloadBytes,
          datosAsociados: prefijoAad,
          destino: salida,
        );
      } on PayloadNoAutenticado catch (e) {
        return PortableContenidoDanado(e.detalle);
      } finally {
        await entrada.close();
        await salida.close();
      }

      final respaldo = respaldoDestino ?? File(p.join(staging.path, 'respaldo_v2.zip'));
      final PayloadLeido contenido;
      try {
        contenido = await PayloadPortable.extraer(payload: payload, respaldoDestino: respaldo);
      } on PayloadPrivadoInvalido catch (e) {
        return PortableContenidoDanado(e.detalle);
      } finally {
        // El payload descifrado lleva dentro el registro de la clave AES.
        // No espera al `finally` de abajo: muere en cuanto se ha leído,
        // incluso si lo que sigue falla.
        _borrar(payload);
      }

      // El respaldo interno se juzga con la MISMA vara que usaría una
      // restauración: hashes por archivo, PRAGMAs y adjuntos.
      final validacion = await _validador.ejecutar(
        rutaZip: respaldo.path,
        appSchemaVersionActual: appSchemaVersionActual,
      );
      if (validacion is! PaqueteRespaldoValido) {
        return PortableRespaldoInternoInvalido(validacion);
      }
      await validacion.staging.delete(recursive: true);

      return PortableVerificado(
        informacion: InformacionPortable(
          creadoEn: leido.cabecera.createdAt,
          appSchemaVersion: leido.cabecera.appSchemaVersion,
          appVersion: leido.cabecera.appVersion,
          bytes: await archivo.length(),
          backupSetId: leido.cabecera.backupSetId,
          tieneEnvolturaDeFrase: leido.tieneEnvolturaDeFrase,
          tieneEnvolturaDeClaveRecuperacion: leido.tieneEnvolturaDeClaveRecuperacion,
        ),
        claveAes: contenido.claveAes,
        backupSetIdPayload: contenido.backupSetId,
      );
    } catch (e) {
      return PortableVerificarErrorInesperado(e.toString());
    } finally {
      // Aquí ha vivido la base de datos en claro, así que se borra
      // siempre. Antes se conservaba el directorio entero cuando el
      // llamador pedía `respaldoDestino`, pero ese destino es suyo y vive
      // fuera de aquí: lo único que se estaba preservando era la copia en
      // claro. Sólo se respeta el caso en que el destino pedido esté
      // dentro de este directorio, y entonces se borra lo demás.
      _limpiarStaging(staging, conservar: respaldoDestino);
    }
  }

  /// Borra [staging] salvo el archivo [conservar], si éste vive dentro.
  void _limpiarStaging(Directory staging, {File? conservar}) {
    if (!staging.existsSync()) return;

    final protegido = conservar == null ? null : p.canonicalize(conservar.path);
    final dentro = protegido != null && p.isWithin(p.canonicalize(staging.path), protegido);

    if (!dentro) {
      try {
        staging.deleteSync(recursive: true);
      } on FileSystemException {
        // Se limpiará al arrancar.
      }
      return;
    }

    for (final hijo in staging.listSync(recursive: false)) {
      if (hijo is File && p.canonicalize(hijo.path) == protegido) continue;
      try {
        hijo.deleteSync(recursive: true);
      } on FileSystemException {
        // Se limpiará al arrancar.
      }
    }
  }

  /// Borrado a prueba de fallos: un archivo que ya no está, o que el
  /// sistema no deja borrar ahora, no puede tumbar una verificación.
  void _borrar(File archivo) {
    try {
      if (archivo.existsSync()) archivo.deleteSync();
    } on FileSystemException {
      // Se limpiará al arrancar.
    }
  }

  /// La MWK del paquete, por cualquiera de las dos puertas.
  Uint8List? _abrirMwk({required ContenedorLeido leido, String? frase, String? claveRecuperacionTexto}) {
    final prefijoConfiguracion = ConfiguracionRecuperacion.prefijoAadConfiguracion(leido.cabecera.backupSetId);

    if (frase != null) {
      for (final envoltura in leido.envolturas.where((e) => e.tipo == TipoEnvoltura.frase)) {
        final mwk = _sobre.abrirConFrase(envoltura: envoltura, frase: frase, prefijoAad: prefijoConfiguracion);
        if (mwk != null) return mwk;
      }
    }
    if (claveRecuperacionTexto != null) {
      final bytes = ClaveRecuperacion.interpretar(claveRecuperacionTexto);
      if (bytes == null) return null;
      for (final envoltura in leido.envolturas.where((e) => e.tipo == TipoEnvoltura.claveRecuperacion)) {
        final mwk = _sobre.abrirConClaveRecuperacion(
          envoltura: envoltura,
          claveRecuperacion: bytes,
          prefijoAad: prefijoConfiguracion,
        );
        if (mwk != null) return mwk;
      }
    }
    return null;
  }

  Future<ContenedorLeido> _leerCabecera(File archivo) async {
    final raf = await archivo.open();
    try {
      final zona = await raf.read(ContenedorPortable.zonaCabecera);
      if (zona.length != ContenedorPortable.zonaCabecera) {
        throw const ContenedorInvalido(MotivoContenedorInvalido.demasiadoCorto);
      }
      return LectorContenedor.leer(zonaCabecera: zona, tamanoArchivo: await archivo.length());
    } finally {
      await raf.close();
    }
  }
}
