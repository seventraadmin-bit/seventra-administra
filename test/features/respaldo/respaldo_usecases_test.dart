// Etapa 14C (Respaldo y restauración) — pruebas de los 4 casos de uso
// de dominio con archivos reales (sqlite3 + zip), sin pasar por
// AppPaths/path_provider (los use cases reciben rutas planas, mismo
// criterio que AttachmentStorage).

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:riseg_one/features/respaldo/domain/usecases/aplicar_restauracion_pendiente_usecase.dart';
import 'package:riseg_one/features/respaldo/domain/usecases/crear_respaldo_usecase.dart';
import 'package:riseg_one/features/respaldo/domain/usecases/preparar_restauracion_usecase.dart';
import 'package:riseg_one/features/respaldo/domain/usecases/validar_paquete_respaldo_usecase.dart';

/// Crea un `.sqlite` real y mínimo (sin pasar por Drift/AppDatabase —
/// los use cases de este archivo solo les importan bytes, `PRAGMA
/// user_version` e `integrity_check`, nunca el esquema de RISEG ONE).
void _crearSqliteDePrueba(String ruta, {int userVersion = 44}) {
  final db = sqlite3.open(ruta);
  db.execute('CREATE TABLE t (x INTEGER)');
  db.execute('INSERT INTO t VALUES (1)');
  db.userVersion = userVersion;
  db.dispose();
}

void main() {
  late Directory raiz;

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('riseg_respaldo_test_');
  });

  tearDown(() {
    // Windows a veces retiene un lock transitorio sobre un archivo
    // recién cerrado (antivirus/indexado) — no es una falla real del
    // caso de uso, así que la limpieza no debe reventar la prueba; el
    // directorio de todos modos vive bajo `Directory.systemTemp`.
    try {
      if (raiz.existsSync()) raiz.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('CrearRespaldoUseCase', () {
    test('produce un .zip con sqlite + adjuntos + manifest.json válido', () async {
      final databaseFile = p.join(raiz.path, 'riseg_one.sqlite');
      _crearSqliteDePrueba(databaseFile);

      final attachmentsDir = Directory(p.join(raiz.path, 'attachments'))..createSync();
      File(p.join(attachmentsDir.path, 'foto.jpg')).writeAsStringSync('contenido-foto');

      final destinoZip = p.join(raiz.path, 'salida.zip');
      final resultado = await CrearRespaldoUseCase(databaseFile: databaseFile, attachmentsDir: attachmentsDir.path)
          .ejecutar(destinoZip: destinoZip);

      expect(resultado, isA<RespaldoCreado>());
      final creado = resultado as RespaldoCreado;
      expect(creado.manifiesto.appSchemaVersion, 44);
      expect(creado.manifiesto.integridadVerificada, isTrue);
      expect(creado.manifiesto.archivosAdjuntos, 1);

      final archivo = ZipDecoder().decodeBytes(File(destinoZip).readAsBytesSync());
      final nombres = archivo.files.map((f) => f.name).toSet();
      expect(nombres, contains('riseg_one.sqlite'));
      expect(nombres, contains('manifest.json'));
      expect(nombres.any((n) => n == 'attachments/foto.jpg'), isTrue);
    });

    test('sin carpeta de adjuntos, el manifiesto reporta cero y el .zip no incluye attachments/', () async {
      final databaseFile = p.join(raiz.path, 'riseg_one.sqlite');
      _crearSqliteDePrueba(databaseFile);

      final destinoZip = p.join(raiz.path, 'salida.zip');
      final resultado = await CrearRespaldoUseCase(
        databaseFile: databaseFile,
        attachmentsDir: p.join(raiz.path, 'attachments_inexistente'),
      ).ejecutar(destinoZip: destinoZip);

      expect(resultado, isA<RespaldoCreado>());
      expect((resultado as RespaldoCreado).manifiesto.archivosAdjuntos, 0);

      final archivo = ZipDecoder().decodeBytes(File(destinoZip).readAsBytesSync());
      expect(archivo.files.any((f) => f.name.startsWith('attachments/')), isFalse);
    });

    test('base de datos inexistente produce RespaldoErrorInesperado, sin crear el .zip', () async {
      final destinoZip = p.join(raiz.path, 'salida.zip');
      final resultado = await CrearRespaldoUseCase(
        databaseFile: p.join(raiz.path, 'no-existe.sqlite'),
        attachmentsDir: p.join(raiz.path, 'attachments'),
      ).ejecutar(destinoZip: destinoZip);

      expect(resultado, isA<RespaldoErrorInesperado>());
      expect(File(destinoZip).existsSync(), isFalse);
    });
  });

  group('ValidarPaqueteRespaldoUseCase', () {
    Future<String> crearZipValido({int userVersion = 44}) async {
      final databaseFile = p.join(raiz.path, 'origen_${userVersion}_.sqlite');
      _crearSqliteDePrueba(databaseFile, userVersion: userVersion);
      final destinoZip = p.join(raiz.path, 'valido_$userVersion.zip');
      final resultado =
          await CrearRespaldoUseCase(databaseFile: databaseFile, attachmentsDir: p.join(raiz.path, 'no-existe'))
              .ejecutar(destinoZip: destinoZip);
      expect(resultado, isA<RespaldoCreado>());
      return destinoZip;
    }

    test('paquete válido con versión igual o menor a la actual se acepta', () async {
      final zip = await crearZipValido(userVersion: 44);
      final resultado =
          await ValidarPaqueteRespaldoUseCase().ejecutar(rutaZip: zip, appSchemaVersionActual: 44);
      expect(resultado, isA<PaqueteRespaldoValido>());
      await (resultado as PaqueteRespaldoValido).staging.delete(recursive: true);
    });

    test('paquete con versión más nueva que la app actual se rechaza', () async {
      final zip = await crearZipValido(userVersion: 50);
      final resultado =
          await ValidarPaqueteRespaldoUseCase().ejecutar(rutaZip: zip, appSchemaVersionActual: 44);
      expect(resultado, isA<PaqueteRespaldoVersionMasNueva>());
      final rechazado = resultado as PaqueteRespaldoVersionMasNueva;
      expect(rechazado.versionPaquete, 50);
      expect(rechazado.versionApp, 44);
    });

    test('zip sin manifest.json se rechaza como paquete inválido', () async {
      final destinoZip = p.join(raiz.path, 'sin_manifest.zip');
      final encoder = ZipFileEncoder();
      encoder.create(destinoZip);
      final databaseFile = p.join(raiz.path, 'origen_suelto.sqlite');
      _crearSqliteDePrueba(databaseFile);
      await encoder.addFile(File(databaseFile), 'riseg_one.sqlite');
      await encoder.close();

      final resultado =
          await ValidarPaqueteRespaldoUseCase().ejecutar(rutaZip: destinoZip, appSchemaVersionActual: 44);
      expect(resultado, isA<PaqueteRespaldoInvalido>());
    });

    test('archivo que no es un .zip se rechaza como paquete inválido', () async {
      final noZip = p.join(raiz.path, 'no_es_zip.zip');
      File(noZip).writeAsStringSync('esto no es un zip');

      final resultado =
          await ValidarPaqueteRespaldoUseCase().ejecutar(rutaZip: noZip, appSchemaVersionActual: 44);
      expect(resultado, isA<PaqueteRespaldoInvalido>());
    });
  });

  group('PrepararRestauracionUseCase', () {
    late String backupsDir;
    late String restorePendingDir;
    late String restorePendingMarkerFile;
    late String databaseFileOrigen;

    setUp(() {
      backupsDir = p.join(raiz.path, 'backups');
      restorePendingDir = p.join(raiz.path, 'restore_pending');
      restorePendingMarkerFile = p.join(raiz.path, 'restore_pending.json');
      databaseFileOrigen = p.join(raiz.path, 'riseg_one.sqlite');
      _crearSqliteDePrueba(databaseFileOrigen);
    });

    PrepararRestauracionUseCase construir() => PrepararRestauracionUseCase(
          backupsDir: backupsDir,
          restorePendingDir: restorePendingDir,
          restorePendingMarkerFile: restorePendingMarkerFile,
          validar: ValidarPaqueteRespaldoUseCase(),
          crearRespaldo: CrearRespaldoUseCase(databaseFile: databaseFileOrigen, attachmentsDir: p.join(raiz.path, 'attachments')),
        );

    test('paquete válido: prepara la restauración, crea respaldo preventivo y deja el marcador', () async {
      final attachmentsOrigenParaZip = Directory(p.join(raiz.path, 'attachments_para_zip'))..createSync();
      File(p.join(attachmentsOrigenParaZip.path, 'doc.pdf')).writeAsStringSync('doc');
      final databaseFileParaZip = p.join(raiz.path, 'origen_para_zip.sqlite');
      _crearSqliteDePrueba(databaseFileParaZip);
      final zipCandidato = p.join(raiz.path, 'candidato.zip');
      final creado = await CrearRespaldoUseCase(databaseFile: databaseFileParaZip, attachmentsDir: attachmentsOrigenParaZip.path)
          .ejecutar(destinoZip: zipCandidato);
      expect(creado, isA<RespaldoCreado>());

      final resultado = await construir().ejecutar(rutaZip: zipCandidato, appSchemaVersionActual: 44);

      expect(resultado, isA<RestauracionPreparada>());
      expect(File(restorePendingMarkerFile).existsSync(), isTrue);
      expect(File(p.join(restorePendingDir, 'riseg_one.sqlite')).existsSync(), isTrue);
      expect(File(p.join(restorePendingDir, 'attachments', 'doc.pdf')).existsSync(), isTrue);
      expect(Directory(backupsDir).listSync().where((e) => e.path.endsWith('.zip')), isNotEmpty);
    });

    test('paquete inválido: se rechaza sin crear marcador ni respaldo preventivo', () async {
      final noZip = p.join(raiz.path, 'invalido.zip');
      File(noZip).writeAsStringSync('no es un zip');

      final resultado = await construir().ejecutar(rutaZip: noZip, appSchemaVersionActual: 44);

      expect(resultado, isA<RestauracionPaqueteInvalido>());
      expect(File(restorePendingMarkerFile).existsSync(), isFalse);
      expect(Directory(backupsDir).existsSync(), isFalse);
    });

    test('versión más nueva que la app actual: se rechaza sin tocar nada', () async {
      final databaseFileNuevo = p.join(raiz.path, 'origen_nuevo.sqlite');
      _crearSqliteDePrueba(databaseFileNuevo, userVersion: 99);
      final zipCandidato = p.join(raiz.path, 'candidato_nuevo.zip');
      await CrearRespaldoUseCase(databaseFile: databaseFileNuevo, attachmentsDir: p.join(raiz.path, 'no-existe'))
          .ejecutar(destinoZip: zipCandidato);

      final resultado = await construir().ejecutar(rutaZip: zipCandidato, appSchemaVersionActual: 44);

      expect(resultado, isA<RestauracionVersionMasNueva>());
      expect(File(restorePendingMarkerFile).existsSync(), isFalse);
    });
  });

  group('AplicarRestauracionPendienteUseCase', () {
    late String databaseFile;
    late String attachmentsDir;
    late String restorePendingDir;
    late String restorePendingMarkerFile;

    setUp(() {
      databaseFile = p.join(raiz.path, 'riseg_one.sqlite');
      attachmentsDir = p.join(raiz.path, 'attachments');
      restorePendingDir = p.join(raiz.path, 'restore_pending');
      restorePendingMarkerFile = p.join(raiz.path, 'restore_pending.json');
    });

    AplicarRestauracionPendienteUseCase construir() => AplicarRestauracionPendienteUseCase(
          databaseFile: databaseFile,
          attachmentsDir: attachmentsDir,
          restorePendingDir: restorePendingDir,
          restorePendingMarkerFile: restorePendingMarkerFile,
        );

    test('sin marcador, no hace nada y retorna false', () async {
      _crearSqliteDePrueba(databaseFile, userVersion: 10);

      final aplicada = await construir().ejecutar();

      expect(aplicada, isFalse);
      final db = sqlite3.open(databaseFile, mode: OpenMode.readOnly);
      expect(db.userVersion, 10);
      db.dispose();
    });

    test('con marcador presente, sustituye sqlite y adjuntos, borra staging y marcador', () async {
      _crearSqliteDePrueba(databaseFile, userVersion: 10);
      Directory(attachmentsDir).createSync();
      File(p.join(attachmentsDir, 'viejo.txt')).writeAsStringSync('viejo');

      Directory(restorePendingDir).createSync(recursive: true);
      _crearSqliteDePrueba(p.join(restorePendingDir, 'riseg_one.sqlite'), userVersion: 44);
      final attachmentsStaged = Directory(p.join(restorePendingDir, 'attachments'))..createSync();
      File(p.join(attachmentsStaged.path, 'nuevo.txt')).writeAsStringSync('nuevo');
      File(restorePendingMarkerFile).writeAsStringSync(jsonEncode({'preparedAt': DateTime.now().toIso8601String()}));

      final aplicada = await construir().ejecutar();

      expect(aplicada, isTrue);
      final db = sqlite3.open(databaseFile, mode: OpenMode.readOnly);
      expect(db.userVersion, 44);
      db.dispose();
      expect(File(p.join(attachmentsDir, 'nuevo.txt')).existsSync(), isTrue);
      expect(File(p.join(attachmentsDir, 'viejo.txt')).existsSync(), isFalse);
      expect(Directory(restorePendingDir).existsSync(), isFalse);
      expect(File(restorePendingMarkerFile).existsSync(), isFalse);
    });
  });
}
