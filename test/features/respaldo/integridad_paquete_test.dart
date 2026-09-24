// Etapa 4B — un respaldo tiene que poder demostrar que llegó entero.
//
// Antes el manifiesto contaba adjuntos y nada más: cuarenta declarados,
// cuarenta presentes, uno con los bytes cambiados, y el paquete se daba
// por bueno. La corrupción se descubría el día que alguien abría ese
// PDF. Ahora cada archivo irremplazable viaja con su tamaño y su
// SHA-256, y el mismo validador que usa Restaurar los comprueba.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:riseg_one/features/respaldo/domain/manifest_respaldo.dart';
import 'package:riseg_one/features/respaldo/domain/rutas_paquete.dart';
import 'package:riseg_one/features/respaldo/domain/usecases/crear_respaldo_usecase.dart';
import 'package:riseg_one/features/respaldo/domain/usecases/validar_paquete_respaldo_usecase.dart';

void main() {
  /// Carpeta que CONTIENE a [raiz]. Existe para que una ruta de escape
  /// (`../fuera.txt`) aterrice aquí dentro y no en la carpeta temporal
  /// del sistema, que es compartida: comprobar allí que "no se escribió
  /// fuera" convierte cualquier archivo ajeno con ese nombre en un
  /// fallo de esta prueba.
  late Directory contenedor;
  late Directory raiz;
  late String databaseFile;
  late String attachmentsDir;
  late String destinoZip;

  setUp(() {
    contenedor = Directory.systemTemp.createTempSync('riseg_integridad_');
    raiz = Directory(p.join(contenedor.path, 'caja'))..createSync();
    databaseFile = p.join(raiz.path, 'riseg_one.sqlite');
    attachmentsDir = p.join(raiz.path, 'attachments');
    destinoZip = p.join(raiz.path, 'respaldo.zip');

    final db = sqlite3.open(databaseFile);
    db.execute('PRAGMA user_version = 44');
    db.execute('CREATE TABLE empleado (id INTEGER PRIMARY KEY, nombre TEXT)');
    db.execute("INSERT INTO empleado VALUES (1, 'JUAN')");
    db.dispose();

    Directory(attachmentsDir).createSync(recursive: true);
    File(p.join(attachmentsDir, 'foto.jpg')).writeAsStringSync('contenido de la foto');
    Directory(p.join(attachmentsDir, 'vehiculos')).createSync();
    File(p.join(attachmentsDir, 'vehiculos', 'poliza.pdf')).writeAsStringSync('contenido de la poliza');
  });

  tearDown(() => contenedor.deleteSync(recursive: true));

  CrearRespaldoUseCase crear() => CrearRespaldoUseCase(databaseFile: databaseFile, attachmentsDir: attachmentsDir);

  Future<ResultadoValidarPaqueteRespaldo> validar(String zip, {int versionApp = 44}) =>
      ValidarPaqueteRespaldoUseCase().ejecutar(rutaZip: zip, appSchemaVersionActual: versionApp);

  /// Reescribe un `.zip` cambiando o quitando entradas — así se fabrica
  /// la corrupción exacta que cada prueba necesita.
  Future<void> reescribirZip(
    String zip, {
    Map<String, List<int>> reemplazos = const {},
    Set<String> quitar = const {},
    Map<String, List<int>> agregar = const {},
  }) async {
    final entrada = InputFileStream(zip);
    final archivo = ZipDecoder().decodeBuffer(entrada);
    final contenidos = <String, List<int>>{};
    for (final e in archivo) {
      if (e.isFile) contenidos[e.name] = e.content as List<int>;
    }
    await entrada.close();

    contenidos.addAll(reemplazos);
    for (final k in quitar) {
      contenidos.remove(k);
    }
    contenidos.addAll(agregar);

    await File(zip).delete();
    final salida = ZipFileEncoder();
    salida.create(zip);
    for (final e in contenidos.entries) {
      salida.addArchiveFile(ArchiveFile(e.key, e.value.length, e.value));
    }
    await salida.close();
  }

  Future<Map<String, dynamic>> manifiestoDe(String zip) async {
    final entrada = InputFileStream(zip);
    final archivo = ZipDecoder().decodeBuffer(entrada);
    for (final e in archivo) {
      if (e.name == RutasPaquete.nombreManifiesto) {
        final json = jsonDecode(utf8.decode(e.content as List<int>)) as Map<String, dynamic>;
        await entrada.close();
        return json;
      }
    }
    await entrada.close();
    throw StateError('sin manifiesto');
  }

  group('Creación', () {
    test('1-4. el paquete trae base, adjuntos y un manifiesto con hash y rutas relativas', () async {
      final resultado = await crear().ejecutar(destinoZip: destinoZip);

      expect(resultado, isA<RespaldoCreado>());
      final manifiesto = (resultado as RespaldoCreado).manifiesto;
      expect(manifiesto.formatVersion, 2);
      expect(manifiesto.capacidades, contains(ManifestRespaldo.capacidadIntegridad));
      expect(manifiesto.baseDatos!.sha256, hasLength(64));
      expect(manifiesto.adjuntos, hasLength(2));

      for (final a in manifiesto.adjuntos) {
        expect(a.sha256, hasLength(64));
        expect(a.bytes, greaterThan(0));
        expect(p.isAbsolute(a.rutaRelativa), isFalse, reason: 'nunca una ruta absoluta en el manifiesto');
        expect(a.rutaRelativa, isNot(contains(r'\')), reason: 'separador de paquete, no de Windows');
      }
      expect(manifiesto.adjuntos.map((a) => a.rutaRelativa), containsAll(['foto.jpg', 'vehiculos/poliza.pdf']));
    });

    test('7. un respaldo recién creado pasa el validador que usaría Restaurar', () async {
      await crear().ejecutar(destinoZip: destinoZip);

      final validacion = await validar(destinoZip);

      expect(validacion, isA<PaqueteRespaldoValido>());
      expect((validacion as PaqueteRespaldoValido).verificacionCompleta, isTrue);
      await validacion.staging.delete(recursive: true);
    });

    test('9. sin adjuntos el paquete es válido y el manifiesto los reporta en cero', () async {
      Directory(attachmentsDir).deleteSync(recursive: true);

      final resultado = await crear().ejecutar(destinoZip: destinoZip);

      expect(resultado, isA<RespaldoCreado>());
      expect((resultado as RespaldoCreado).manifiesto.adjuntos, isEmpty);
      final validacion = await validar(destinoZip);
      expect(validacion, isA<PaqueteRespaldoValido>());
      await (validacion as PaqueteRespaldoValido).staging.delete(recursive: true);
    });

    test('6. un destino imposible no deja ningún archivo con el nombre definitivo', () async {
      final imposible = p.join(raiz.path, 'no', 'existe', 'x.zip');
      Directory(p.join(raiz.path, 'no')).createSync();
      File(p.join(raiz.path, 'no', 'existe')).writeAsStringSync('soy un archivo, no una carpeta');

      final resultado = await crear().ejecutar(destinoZip: imposible);

      expect(resultado, isA<RespaldoDestinoNoDisponible>());
      expect(File(imposible).existsSync(), isFalse);
      expect(
        File('$imposible${CrearRespaldoUseCase.sufijoParcial}').existsSync(),
        isFalse,
        reason: 'y tampoco queda el temporal',
      );
    });

    test('8. una base con referencias rotas no produce respaldo', () async {
      final db = sqlite3.open(databaseFile);
      db.execute('PRAGMA foreign_keys = OFF');
      db.execute('CREATE TABLE hijo (id INTEGER PRIMARY KEY, padre INTEGER REFERENCES empleado(id))');
      db.execute('INSERT INTO hijo VALUES (1, 999)');
      db.dispose();

      final resultado = await crear().ejecutar(destinoZip: destinoZip);

      expect(resultado, isA<RespaldoIntegridadFallida>());
      expect(File(destinoZip).existsSync(), isFalse);
    });
  });

  group('Validación detecta corrupción', () {
    test('11. base de datos alterada', () async {
      await crear().ejecutar(destinoZip: destinoZip);
      await reescribirZip(destinoZip, reemplazos: {RutasPaquete.nombreBaseDatos: utf8.encode('ya no soy sqlite')});

      final validacion = await validar(destinoZip);

      expect(validacion, isA<PaqueteRespaldoInvalido>());
      expect((validacion as PaqueteRespaldoInvalido).motivo, MotivoPaqueteInvalido.baseDatosAlterada);
    });

    test('12. adjunto alterado — el caso exacto que antes pasaba inadvertido', () async {
      await crear().ejecutar(destinoZip: destinoZip);
      // Mismo número de archivos, mismo nombre: sólo cambian los bytes.
      await reescribirZip(destinoZip, reemplazos: {'attachments/foto.jpg': utf8.encode('contenido corrompido!')});

      final validacion = await validar(destinoZip);

      expect(validacion, isA<PaqueteRespaldoInvalido>());
      expect((validacion as PaqueteRespaldoInvalido).motivo, MotivoPaqueteInvalido.adjuntoAlterado);
    });

    test('15. adjunto del mismo tamaño pero distinto contenido', () async {
      await crear().ejecutar(destinoZip: destinoZip);
      final original = 'contenido de la foto';
      final mismoLargo = 'CONTENIDO DE LA FOTO';
      expect(mismoLargo.length, original.length);
      await reescribirZip(destinoZip, reemplazos: {'attachments/foto.jpg': utf8.encode(mismoLargo)});

      final validacion = await validar(destinoZip);

      expect(validacion, isA<PaqueteRespaldoInvalido>(), reason: 'el tamaño coincide: sólo el hash puede delatarlo');
    });

    test('13. adjunto faltante', () async {
      await crear().ejecutar(destinoZip: destinoZip);
      await reescribirZip(destinoZip, quitar: {'attachments/foto.jpg'});

      final validacion = await validar(destinoZip);

      expect((validacion as PaqueteRespaldoInvalido).motivo, MotivoPaqueteInvalido.adjuntoFaltante);
    });

    test('14. adjunto extra que el manifiesto no declara', () async {
      await crear().ejecutar(destinoZip: destinoZip);
      await reescribirZip(destinoZip, agregar: {'attachments/colado.txt': utf8.encode('no estaba')});

      final validacion = await validar(destinoZip);

      expect(
        (validacion as PaqueteRespaldoInvalido).motivo,
        MotivoPaqueteInvalido.adjuntoNoDeclarado,
        reason: 'el manifiesto describe EXACTAMENTE lo que se va a restaurar',
      );
    });

    test('16. manifiesto corrupto', () async {
      await crear().ejecutar(destinoZip: destinoZip);
      await reescribirZip(destinoZip, reemplazos: {RutasPaquete.nombreManifiesto: utf8.encode('{no es json')});

      final validacion = await validar(destinoZip);

      expect((validacion as PaqueteRespaldoInvalido).motivo, MotivoPaqueteInvalido.manifiestoDanado);
    });

    test('17. sin manifiesto', () async {
      await crear().ejecutar(destinoZip: destinoZip);
      await reescribirZip(destinoZip, quitar: {RutasPaquete.nombreManifiesto});

      final validacion = await validar(destinoZip);

      expect((validacion as PaqueteRespaldoInvalido).motivo, MotivoPaqueteInvalido.faltaManifiesto);
    });

    test('18. sin base de datos', () async {
      await crear().ejecutar(destinoZip: destinoZip);
      await reescribirZip(destinoZip, quitar: {RutasPaquete.nombreBaseDatos});

      final validacion = await validar(destinoZip);

      expect((validacion as PaqueteRespaldoInvalido).motivo, MotivoPaqueteInvalido.faltaBaseDatos);
    });

    test('21. esquema más nuevo que esta versión de la aplicación', () async {
      await crear().ejecutar(destinoZip: destinoZip);

      final validacion = await validar(destinoZip, versionApp: 10);

      expect(validacion, isA<PaqueteRespaldoVersionMasNueva>());
    });

    test('un formato que esta versión no conoce se rechaza sin intentar nada', () async {
      await crear().ejecutar(destinoZip: destinoZip);
      final json = await manifiestoDe(destinoZip)
        ..['formatVersion'] = 99;
      await reescribirZip(destinoZip, reemplazos: {RutasPaquete.nombreManifiesto: utf8.encode(jsonEncode(json))});

      final validacion = await validar(destinoZip);

      expect((validacion as PaqueteRespaldoInvalido).motivo, MotivoPaqueteInvalido.formatoNoSoportado);
    });
  });

  group('Rutas inseguras', () {
    test('19. una entrada que sale del paquete con ../ se rechaza', () async {
      await crear().ejecutar(destinoZip: destinoZip);
      await reescribirZip(destinoZip, agregar: {'../fuera.txt': utf8.encode('escape')});

      final validacion = await validar(destinoZip);

      expect((validacion as PaqueteRespaldoInvalido).motivo, MotivoPaqueteInvalido.rutaInsegura);
      expect(File(p.join(raiz.path, '..', 'fuera.txt')).existsSync(), isFalse, reason: 'no se escribió fuera');
    });

    test('19b. ../ enterrado entre segmentos también se rechaza', () async {
      await crear().ejecutar(destinoZip: destinoZip);
      await reescribirZip(destinoZip, agregar: {'attachments/sub/../../../fuera.txt': utf8.encode('escape')});

      final validacion = await validar(destinoZip);

      expect((validacion as PaqueteRespaldoInvalido).motivo, MotivoPaqueteInvalido.rutaInsegura);
    });

    test('20. una ruta absoluta de Windows se rechaza', () async {
      await crear().ejecutar(destinoZip: destinoZip);
      await reescribirZip(destinoZip, agregar: {'C:/Windows/System32/colado.txt': utf8.encode('escape')});

      final validacion = await validar(destinoZip);

      expect((validacion as PaqueteRespaldoInvalido).motivo, MotivoPaqueteInvalido.rutaInsegura);
    });

    test('20b. una ruta absoluta POSIX se rechaza', () async {
      await crear().ejecutar(destinoZip: destinoZip);
      await reescribirZip(destinoZip, agregar: {'/etc/colado.txt': utf8.encode('escape')});

      final validacion = await validar(destinoZip);

      expect((validacion as PaqueteRespaldoInvalido).motivo, MotivoPaqueteInvalido.rutaInsegura);
    });

    test('las reglas de ruta segura, directamente', () {
      for (final mala in ['../x', 'a/../../x', '/abs', 'C:/x', r'a\b', '//servidor/x', '', '   ', 'a//b']) {
        expect(RutasPaquete.esSegura(mala), isFalse, reason: 'debería rechazar "$mala"');
      }
      for (final buena in ['foto.jpg', 'vehiculos/poliza.pdf', 'a/b/c/d.txt']) {
        expect(RutasPaquete.esSegura(buena), isTrue, reason: 'debería aceptar "$buena"');
      }
    });
  });

  group('Compatibilidad con el formato anterior', () {
    /// Fabrica un paquete con la forma exacta que producía la Etapa 14C.
    Future<void> crearPaqueteV1(String zip) async {
      final encoder = ZipFileEncoder();
      encoder.create(zip);
      await encoder.addFile(File(databaseFile), RutasPaquete.nombreBaseDatos);
      await encoder.addFile(File(p.join(attachmentsDir, 'foto.jpg')), 'attachments/foto.jpg');
      final manifiesto = utf8.encode(
        jsonEncode({
          'formatVersion': 1,
          'createdAt': DateTime(2026, 1, 1).toIso8601String(),
          'appSchemaVersion': 44,
          'integridadVerificada': true,
          'archivosAdjuntos': 1,
          'bytesAdjuntos': 20,
        }),
      );
      encoder.addArchiveFile(ArchiveFile(RutasPaquete.nombreManifiesto, manifiesto.length, manifiesto));
      await encoder.close();
    }

    test('22. un v1 correcto sigue siendo restaurable, con verificación limitada', () async {
      final zipV1 = p.join(raiz.path, 'v1.zip');
      await crearPaqueteV1(zipV1);

      final validacion = await validar(zipV1);

      expect(validacion, isA<PaqueteRespaldoValido>(), reason: 'no se rompe compatibilidad gratuitamente');
      final valido = validacion as PaqueteRespaldoValido;
      expect(
        valido.verificacionCompleta,
        isFalse,
        reason: 'ese formato no registra huellas: no puede presentarse como verificado',
      );
      expect(valido.manifiesto.formatVersion, 1);
      await valido.staging.delete(recursive: true);
    });

    test('23. un v1 con un adjunto corrupto NO puede fingir verificación completa', () async {
      final zipV1 = p.join(raiz.path, 'v1.zip');
      await crearPaqueteV1(zipV1);
      await reescribirZip(zipV1, reemplazos: {'attachments/foto.jpg': utf8.encode('corrompido')});

      final validacion = await validar(zipV1);

      // Se acepta —no hay forma de saberlo— pero jamás se declara íntegro.
      expect(validacion, isA<PaqueteRespaldoValido>());
      expect((validacion as PaqueteRespaldoValido).verificacionCompleta, isFalse);
      await validacion.staging.delete(recursive: true);
    });

    test('12. un v1 NO se reescribe ni se convierte a v2 al validarlo', () async {
      final zipV1 = p.join(raiz.path, 'v1.zip');
      await crearPaqueteV1(zipV1);
      final antes = await File(zipV1).readAsBytes();

      final validacion = await validar(zipV1);
      await (validacion as PaqueteRespaldoValido).staging.delete(recursive: true);

      expect(
        await File(zipV1).readAsBytes(),
        antes,
        reason: 'un respaldo es un artefacto histórico: se lee según su versión, nunca se actualiza',
      );
    });
  });
}
