// Etapa 4D — crear un `.risegbkp` de verdad y volver a abrirlo.
//
// Aquí ya no se prueban piezas: se prueba el recorrido completo sobre
// archivos reales, con la base de datos real, la clave AES real y el
// motor de respaldo de 4B sin modificar. Lo que importa de estas pruebas
// es que el paquete se abra **por las dos puertas** —frase y clave de
// recuperación— y que un paquete que no se pueda abrir nunca llegue a
// tener nombre definitivo.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/security/aes_gcm_hkdf_streaming.dart';
import 'package:riseg_one/core/security/credential_cipher.dart';
import 'package:riseg_one/features/respaldo/domain/portable/clave_recuperacion.dart';
import 'package:riseg_one/features/respaldo/domain/portable/configuracion_recuperacion.dart';
import 'package:riseg_one/features/respaldo/domain/portable/configurar_recuperacion_usecase.dart';
import 'package:riseg_one/features/respaldo/domain/portable/contenedor_portable.dart';
import 'package:riseg_one/features/respaldo/domain/portable/crear_respaldo_portable_usecase.dart';
import 'package:riseg_one/features/respaldo/domain/portable/kdf_portable.dart';
import 'package:riseg_one/features/respaldo/domain/portable/payload_portable.dart';
import 'package:riseg_one/features/respaldo/domain/portable/sobre_portable.dart';
import 'package:riseg_one/features/respaldo/domain/portable/verificar_respaldo_portable_usecase.dart';

/// Argon2 de mentira: estas pruebas miden el recorrido, no el KDF. Con el
/// real cada verificación costaría casi medio segundo.
class _Argon2Rapido implements GeneradorArgon2 {
  @override
  Uint8List derivar({required Uint8List secreto, required ParametrosArgon2id parametros}) {
    final salida = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      salida[i] = (secreto.isEmpty ? 7 : secreto[i % secreto.length]) ^ parametros.salt[i % parametros.salt.length] ^ i;
    }
    return salida;
  }
}

class _AlmacenEnMemoria implements AlmacenClaveCifrado {
  String? valor;
  @override
  Future<String?> leer() async => valor;
  @override
  Future<void> escribir(String v) async => valor = v;
}

const _frase = 'frase de recuperación de MARLON';

void main() {
  late Directory raiz;
  late String databaseFile;
  late String attachmentsDir;
  late String stagingDir;
  late _AlmacenEnMemoria almacenClave;
  late CredentialCipher cipher;

  /// Sobre con Argon2 rápido, compartido por creación y verificación: si
  /// cada lado derivara distinto, nada abriría.
  SobrePortable sobreRapido() => SobrePortable(derivador: DerivadorKek(argon2: _Argon2Rapido()));

  setUp(() async {
    raiz = Directory.systemTemp.createTempSync('riseg_portable_e2e_');
    databaseFile = p.join(raiz.path, 'riseg_one.sqlite');
    attachmentsDir = p.join(raiz.path, 'attachments');
    stagingDir = p.join(raiz.path, 'staging');
    almacenClave = _AlmacenEnMemoria();
    cipher = CredentialCipher(almacen: almacenClave);

    // Una base REAL de esta build, con secretos cifrados de los tres
    // módulos que comparten la clave AES.
    final db = AppDatabase(openAppDatabaseConnection(databaseFile), almacenClaveCifrado: almacenClave);
    await db.customSelect('SELECT 1').get();
    await db.customStatement(
      "INSERT INTO usuario (id, nombre, nombre_usuario, password_hash, es_maestro, debe_cambiar_password, ciclo_vida_registro, created_at, updated_at) "
      "VALUES ('u-maestro', 'MARLON', 'MARLONRH', 'pbkdf2\$1000\$s\$h', 1, 0, 'activo', 1700000000, 1700000000)",
    );
    final secretoBoveda = await cipher.cifrar('contrasena-del-SAT');
    await db.customStatement(
      'INSERT INTO boveda_credencial (id, nombre, tipo, secreto_cifrado, ciclo_vida_registro, created_at, updated_at) '
      "VALUES ('bc-1', 'RISEG - SAT', 'portal', '$secretoBoveda', 'activo', 1700000000, 1700000000)",
    );
    await db.close();

    Directory(attachmentsDir).createSync(recursive: true);
    File(p.join(attachmentsDir, 'contrato.pdf')).writeAsStringSync('documento irremplazable');
    Directory(stagingDir).createSync(recursive: true);
  });

  tearDown(() {
    try {
      raiz.deleteSync(recursive: true);
    } on FileSystemException {
      // En Windows un handle recién cerrado puede tardar un instante.
    }
  });

  /// Configura la recuperación y devuelve todo lo necesario.
  RecuperacionConfigurada configurar() {
    return ConfigurarRecuperacionUseCase(sobre: sobreRapido()).ejecutar(
      frase: _frase,
      parametros: ParametrosArgon2id(
        memoriaKiB: LimitesArgon2id.memoriaMinimaKiB,
        iteraciones: 1,
        paralelismo: 1,
        salt: Uint8List.fromList(List<int>.generate(16, (i) => i)),
      ),
    );
  }

  CrearRespaldoPortableUseCase creador() => CrearRespaldoPortableUseCase(
    databaseFile: databaseFile,
    attachmentsDir: attachmentsDir,
    stagingDir: stagingDir,
    appVersion: '1.0.0',
    cipher: cipher,
    sobre: sobreRapido(),
    verificador: VerificarRespaldoPortableUseCase(stagingDir: stagingDir, sobre: sobreRapido()),
  );

  VerificarRespaldoPortableUseCase verificador() =>
      VerificarRespaldoPortableUseCase(stagingDir: stagingDir, sobre: sobreRapido());

  Future<ResultadoCrearPortable> crear(ConfiguracionRecuperacion configuracion, {String nombre = 'respaldo'}) {
    return creador().ejecutar(
      destino: p.join(raiz.path, '$nombre${ContenedorPortable.extension}'),
      frase: _frase,
      configuracion: configuracion,
      appSchemaVersion: 93,
    );
  }

  group('Configuración', () {
    test('genera backupSetId, dos envolturas de la misma clave maestra y una clave de recuperación legible', () {
      final r = configurar();

      expect(r.configuracion.backupSetId, hasLength(32));
      expect(r.configuracion.envolturas, hasLength(2));
      expect(r.claveRecuperacionTexto, startsWith('RISEG-'));
      expect(ClaveRecuperacion.interpretar(r.claveRecuperacionTexto), isNotNull);
    });

    test('la frase y la clave de recuperación abren la MISMA clave maestra', () {
      final r = configurar();
      final sobre = sobreRapido();

      final porFrase = r.configuracion.abrirMwkConFrase(frase: _frase, sobre: sobre);
      final porClave = r.configuracion.abrirMwkConClaveRecuperacion(
        claveRecuperacion: ClaveRecuperacion.interpretar(r.claveRecuperacionTexto)!,
        sobre: sobre,
      );

      expect(porFrase, isNotNull);
      expect(porFrase, equals(porClave));
    });

    test('una frase demasiado corta se rechaza por longitud, sin reglas de composición', () {
      expect(() => ConfigurarRecuperacionUseCase().ejecutar(frase: 'corta'), throwsArgumentError);
    });

    test('lo persistido se puede reconstruir tal cual', () {
      final r = configurar();

      final reconstruida = ConfiguracionRecuperacion.desdePersistido(
        backupSetId: r.configuracion.backupSetId,
        formatoVersion: r.configuracion.formatoVersion,
        envolturaFraseJson: r.configuracion.envolturaFraseJson(),
        envolturaClaveRecuperacionJson: r.configuracion.envolturaClaveRecuperacionJson(),
        claveRecuperacionGeneradaEn: r.configuracion.claveRecuperacionGeneradaEn,
      );

      expect(reconstruida, isNotNull);
      expect(reconstruida!.abrirMwkConFrase(frase: _frase, sobre: sobreRapido()), isNotNull);
    });
  });

  group('Creación', () {
    test('produce un .risegbkp con su magic y sin dejar archivos .parcial', () async {
      final r = configurar();

      final resultado = await crear(r.configuracion);

      expect(resultado, isA<PortableCreado>());
      final creado = resultado as PortableCreado;
      final bytes = await File(creado.ruta).openRead(0, 8).first;
      expect(utf8.decode(bytes), 'RISEGBKP');
      expect(creado.bytes, greaterThan(ContenedorPortable.zonaCabecera));

      final sobras = raiz.listSync().whereType<File>().where((f) => f.path.endsWith('.parcial'));
      expect(sobras, isEmpty);
    });

    test('con una frase incorrecta no se escribe nada', () async {
      final r = configurar();

      final resultado = await creador().ejecutar(
        destino: p.join(raiz.path, 'no_debe_existir${ContenedorPortable.extension}'),
        frase: 'frase equivocada pero larga',
        configuracion: r.configuracion,
        appSchemaVersion: 93,
      );

      expect(resultado, isA<PortableCredencialIncorrecta>());
      expect(File(p.join(raiz.path, 'no_debe_existir${ContenedorPortable.extension}')).existsSync(), isFalse);
    });

    test('SIN clave AES en el equipo, FALLA en vez de inventar una', () async {
      final r = configurar();
      // Un equipo sin clave: el Almacén de Credenciales está vacío.
      final sinClave = CrearRespaldoPortableUseCase(
        databaseFile: databaseFile,
        attachmentsDir: attachmentsDir,
        stagingDir: stagingDir,
        appVersion: '1.0.0',
        cipher: CredentialCipher(almacen: _AlmacenEnMemoria()),
        sobre: sobreRapido(),
        verificador: verificador(),
      );

      final resultado = await sinClave.ejecutar(
        destino: p.join(raiz.path, 'sin_clave${ContenedorPortable.extension}'),
        frase: _frase,
        configuracion: r.configuracion,
        appSchemaVersion: 93,
      );

      expect(
        resultado,
        isA<PortableSinClaveDeCifrado>(),
        reason: 'un portable con una clave recién inventada no abriría ni un secreto de los que acompaña',
      );
      expect(File(p.join(raiz.path, 'sin_clave${ContenedorPortable.extension}')).existsSync(), isFalse);
    });

    test('el staging queda limpio: no sobrevive ninguna copia en claro', () async {
      final r = configurar();
      await crear(r.configuracion);

      final restos = Directory(stagingDir).listSync(recursive: true);
      expect(restos, isEmpty, reason: 'ahí vivieron la base y el respaldo en claro');
    });

    test(
      'dos paquetes del mismo conjunto llevan packageId distintos',
      timeout: const Timeout(Duration(minutes: 3)),
      () async {
        final r = configurar();

        final uno = await crear(r.configuracion, nombre: 'uno') as PortableCreado;
        final dos = await crear(r.configuracion, nombre: 'dos') as PortableCreado;

        expect(uno.packageId, isNot(dos.packageId));
      },
    );
  });

  group('Inspección sin credencial', () {
    test('devuelve sólo metadata pública', () async {
      final r = configurar();
      final creado = await crear(r.configuracion) as PortableCreado;

      final info = await verificador().inspeccionar(rutaPaquete: creado.ruta);

      expect(info.appSchemaVersion, 93);
      expect(info.appVersion, '1.0.0');
      expect(info.backupSetId, r.configuracion.backupSetId);
      expect(info.tieneEnvolturaDeFrase, isTrue);
      expect(info.tieneEnvolturaDeClaveRecuperacion, isTrue);
      expect(info.bytes, greaterThan(0));
    });

    test('un archivo que no es un contenedor se rechaza', () async {
      final falso = File(p.join(raiz.path, 'falso.risegbkp'))..writeAsBytesSync(Uint8List(9000));

      await expectLater(verificador().inspeccionar(rutaPaquete: falso.path), throwsA(isA<ContenedorInvalido>()));
    });
  });

  group('Verificación completa', () {
    test('con la FRASE: verificado de arriba abajo', () async {
      final r = configurar();
      final creado = await crear(r.configuracion) as PortableCreado;

      final resultado = await verificador().ejecutar(
        rutaPaquete: creado.ruta,
        frase: _frase,
        appSchemaVersionActual: 93,
      );

      expect(resultado, isA<PortableVerificado>());
      final ok = resultado as PortableVerificado;
      expect(ok.keyIdClaveAes, hasLength(32));
      expect(ok.backupSetIdPayload, r.configuracion.backupSetId);
    });

    test('con la CLAVE DE RECUPERACIÓN: el mismo veredicto', () async {
      final r = configurar();
      final creado = await crear(r.configuracion) as PortableCreado;

      final resultado = await verificador().ejecutar(
        rutaPaquete: creado.ruta,
        claveRecuperacionTexto: r.claveRecuperacionTexto,
        appSchemaVersionActual: 93,
      );

      expect(resultado, isA<PortableVerificado>());
    });

    test('la clave de recuperación con guiones, espacios y minúsculas también abre', () async {
      final r = configurar();
      final creado = await crear(r.configuracion) as PortableCreado;
      final tecleada = r.claveRecuperacionTexto.toLowerCase().replaceAll('-', ' ');

      final resultado = await verificador().ejecutar(
        rutaPaquete: creado.ruta,
        claveRecuperacionTexto: tecleada,
        appSchemaVersionActual: 93,
      );

      expect(resultado, isA<PortableVerificado>());
    });

    test('una frase incorrecta y una clave incorrecta dan el MISMO resultado', () async {
      final r = configurar();
      final creado = await crear(r.configuracion) as PortableCreado;
      final v = verificador();

      final porFrase = await v.ejecutar(
        rutaPaquete: creado.ruta,
        frase: 'otra frase larga',
        appSchemaVersionActual: 93,
      );
      final porClave = await v.ejecutar(
        rutaPaquete: creado.ruta,
        claveRecuperacionTexto: ClaveRecuperacion.formatear(Uint8List(20)),
        appSchemaVersionActual: 93,
      );

      expect(porFrase, isA<PortableCredencialIncorrectaOModificado>());
      expect(porClave, isA<PortableCredencialIncorrectaOModificado>());
    });

    test('sin credencial alguna no se verifica nada', () async {
      final r = configurar();
      final creado = await crear(r.configuracion) as PortableCreado;

      expect(
        await verificador().ejecutar(rutaPaquete: creado.ruta, appSchemaVersionActual: 93),
        isA<PortableCredencialIncorrectaOModificado>(),
      );
    });

    test('un bit cambiado en el payload se detecta', () async {
      final r = configurar();
      final creado = await crear(r.configuracion) as PortableCreado;
      final bytes = await File(creado.ruta).readAsBytes();
      bytes[ContenedorPortable.zonaCabecera + 60] ^= 0x01;
      await File(creado.ruta).writeAsBytes(bytes);

      final resultado = await verificador().ejecutar(
        rutaPaquete: creado.ruta,
        frase: _frase,
        appSchemaVersionActual: 93,
      );

      expect(resultado, isA<PortableContenidoDanado>());
    });

    test('truncar el paquete se detecta antes de mirar dentro', () async {
      final r = configurar();
      final creado = await crear(r.configuracion) as PortableCreado;
      final bytes = await File(creado.ruta).readAsBytes();
      await File(creado.ruta).writeAsBytes(Uint8List.sublistView(bytes, 0, bytes.length - 40));

      final resultado = await verificador().ejecutar(
        rutaPaquete: creado.ruta,
        frase: _frase,
        appSchemaVersionActual: 93,
      );

      expect(resultado, isA<PortableEstructuraInvalida>());
      expect((resultado as PortableEstructuraInvalida).motivo, MotivoContenedorInvalido.tamanoInconsistente);
    });

    test('el appSchemaVersion de la cabecera NO es autoridad: manda la base de dentro', () async {
      final r = configurar();
      // Se pide escribir 999 en R1. Es metadata pública y no manda: el
      // validador de 4B vuelve a leer user_version del archivo real,
      // igual que hace al restaurar. Un número en una cabecera no puede
      // decidir si un respaldo es restaurable.
      final creado =
          await creador().ejecutar(
                destino: p.join(raiz.path, 'cabecera_mentirosa${ContenedorPortable.extension}'),
                frase: _frase,
                configuracion: r.configuracion,
                appSchemaVersion: 999,
              )
              as PortableCreado;

      final info = await verificador().inspeccionar(rutaPaquete: creado.ruta);
      expect(info.appSchemaVersion, 999, reason: 'la cabecera dice lo que se le pidió');

      final resultado = await verificador().ejecutar(
        rutaPaquete: creado.ruta,
        frase: _frase,
        appSchemaVersionActual: 93,
      );
      expect(
        resultado,
        isA<PortableVerificado>(),
        reason: 'la base interna sí está en 93; rechazar por la cabecera sería confiar en ella',
      );
    });
  });

  group('El contenido llega intacto y la clave AES viaja dentro', () {
    test('el respaldo interno extraído es un paquete v2 válido con sus adjuntos', () async {
      final r = configurar();
      final creado = await crear(r.configuracion) as PortableCreado;
      final respaldo = File(p.join(raiz.path, 'extraido.zip'));

      final resultado = await verificador().ejecutar(
        rutaPaquete: creado.ruta,
        frase: _frase,
        appSchemaVersionActual: 93,
        respaldoDestino: respaldo,
      );

      expect(resultado, isA<PortableVerificado>());
      expect(respaldo.existsSync(), isTrue);
      expect(await respaldo.length(), greaterThan(0));
    });

    test('la clave AES del paquete es EXACTAMENTE la del equipo', () async {
      final r = configurar();
      final creado = await crear(r.configuracion) as PortableCreado;
      final claveDelEquipo = await cipher.obtenerClaveExistente();

      // Se abre el paquete a mano hasta el registro de clave: es lo que
      // hará una restauración en PC B.
      final raf = await File(creado.ruta).open();
      final zona = await raf.read(ContenedorPortable.zonaCabecera);
      final leido = LectorContenedor.leer(zonaCabecera: zona, tamanoArchivo: await File(creado.ruta).length());
      final sobre = sobreRapido();
      final mwk = r.configuracion.abrirMwkConFrase(frase: _frase, sobre: sobre)!;
      final dek =
          sobre.abrirDek(
            mwk: mwk,
            nonce: leido.dekWrapNonce,
            cifrado: leido.dekWrapCifrado,
            prefijoAad: ContenedorPortable.prefijoAad(zona),
          )!;

      final payload = File(p.join(raiz.path, 'payload.bin'));
      final salida = await payload.open(mode: FileMode.write);
      await raf.setPosition(ContenedorPortable.zonaCabecera);
      await AesGcmHkdfStreaming(ikm: dek, segmentSize: leido.cabecera.segmentSize).descifrarArchivoHacia(
        origen: raf,
        payloadBytes: leido.cabecera.payloadBytes,
        datosAsociados: ContenedorPortable.prefijoAad(zona),
        destino: salida,
      );
      await salida.close();
      await raf.close();

      final contenido = await PayloadPortable.extraer(
        payload: payload,
        respaldoDestino: File(p.join(raiz.path, 'r.zip')),
      );

      expect(contenido.claveAes.clave, equals(claveDelEquipo));
      expect(contenido.claveAes.algoritmo, 'aes-256-gcm');
    });

    test('la clave AES NO aparece en claro en el archivo', () async {
      final r = configurar();
      final creado = await crear(r.configuracion) as PortableCreado;
      final clave = await cipher.obtenerClaveExistente();
      final bytes = await File(creado.ruta).readAsBytes();

      expect(_contiene(bytes, clave), isFalse, reason: 'la clave sólo puede existir dentro del payload cifrado');
      // Y tampoco su representación hexadecimal.
      final hex = clave.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(utf8.decode(bytes, allowMalformed: true), isNot(contains(hex)));
    });

    test('ni la frase ni la clave de recuperación aparecen en el archivo', () async {
      final r = configurar();
      final creado = await crear(r.configuracion) as PortableCreado;
      final texto = utf8.decode(await File(creado.ruta).readAsBytes(), allowMalformed: true);

      expect(texto, isNot(contains(_frase)));
      expect(texto, isNot(contains(r.claveRecuperacionTexto)));
      expect(texto, isNot(contains(r.claveRecuperacionTexto.replaceAll('-', ''))));
    });

    test('la cabecera pública no filtra datos de negocio', () async {
      final r = configurar();
      final creado = await crear(r.configuracion) as PortableCreado;
      final zona = await File(creado.ruta).openRead(0, ContenedorPortable.zonaCabecera).first;
      final texto = utf8.decode(zona, allowMalformed: true);

      for (final prohibido in ['MARLON', 'MARLONRH', 'SAT', 'contrato.pdf', 'contrasena']) {
        expect(texto, isNot(contains(prohibido)), reason: 'R1/R3 no pueden hablar de $prohibido');
      }
    });
  });

  group('Cambiar frase y regenerar clave de recuperación', () {
    test('cambiar la frase no toca la clave maestra ni la otra puerta', () {
      final r = configurar();
      final caso = ConfigurarRecuperacionUseCase(sobre: sobreRapido());
      final sobre = sobreRapido();
      final mwkAntes = r.configuracion.abrirMwkConFrase(frase: _frase, sobre: sobre)!;

      final nueva = caso.cambiarFrase(
        actual: r.configuracion,
        fraseActual: _frase,
        fraseNueva: 'una frase completamente nueva',
      );

      expect(nueva, isNotNull);
      expect(nueva!.abrirMwkConFrase(frase: 'una frase completamente nueva', sobre: sobre), equals(mwkAntes));
      expect(nueva.abrirMwkConFrase(frase: _frase, sobre: sobre), isNull, reason: 'la vieja ya no abre la nueva');
      expect(
        nueva.abrirMwkConClaveRecuperacion(
          claveRecuperacion: ClaveRecuperacion.interpretar(r.claveRecuperacionTexto)!,
          sobre: sobre,
        ),
        equals(mwkAntes),
        reason: 'la clave de recuperación sigue valiendo',
      );
    });

    test('los paquetes ya creados siguen abriéndose con la frase anterior', () async {
      final r = configurar();
      final creado = await crear(r.configuracion) as PortableCreado;
      ConfigurarRecuperacionUseCase(
        sobre: sobreRapido(),
      ).cambiarFrase(actual: r.configuracion, fraseActual: _frase, fraseNueva: 'otra frase bien larga');

      // El archivo es una fotografía: lleva su propio bloque de
      // recuperación y la frase nueva no existe para él.
      final resultado = await verificador().ejecutar(
        rutaPaquete: creado.ruta,
        frase: _frase,
        appSchemaVersionActual: 93,
      );

      expect(resultado, isA<PortableVerificado>());
    });

    test('con la frase incorrecta no se puede cambiar la frase', () {
      final r = configurar();

      expect(
        ConfigurarRecuperacionUseCase(
          sobre: sobreRapido(),
        ).cambiarFrase(actual: r.configuracion, fraseActual: 'no es la frase', fraseNueva: 'una frase nueva y larga'),
        isNull,
      );
    });

    test('regenerar la clave de recuperación mantiene la misma clave maestra y la frase', () {
      final r = configurar();
      final sobre = sobreRapido();
      final mwkAntes = r.configuracion.abrirMwkConFrase(frase: _frase, sobre: sobre)!;

      final nueva = ConfigurarRecuperacionUseCase(
        sobre: sobreRapido(),
      ).regenerarClaveRecuperacion(actual: r.configuracion, frase: _frase);

      expect(nueva, isNotNull);
      expect(nueva!.claveRecuperacionTexto, isNot(r.claveRecuperacionTexto));
      expect(nueva.configuracion.abrirMwkConFrase(frase: _frase, sobre: sobre), equals(mwkAntes));
      expect(
        nueva.configuracion.abrirMwkConClaveRecuperacion(
          claveRecuperacion: ClaveRecuperacion.interpretar(nueva.claveRecuperacionTexto)!,
          sobre: sobre,
        ),
        equals(mwkAntes),
      );
      expect(
        nueva.configuracion.abrirMwkConClaveRecuperacion(
          claveRecuperacion: ClaveRecuperacion.interpretar(r.claveRecuperacionTexto)!,
          sobre: sobre,
        ),
        isNull,
        reason: 'la clave anterior deja de valer para la configuración nueva',
      );
    });
  });
}

bool _contiene(Uint8List heno, Uint8List aguja) {
  if (aguja.isEmpty || aguja.length > heno.length) return false;
  for (var i = 0; i <= heno.length - aguja.length; i++) {
    var igual = true;
    for (var j = 0; j < aguja.length; j++) {
      if (heno[i + j] != aguja[j]) {
        igual = false;
        break;
      }
    }
    if (igual) return true;
  }
  return false;
}
