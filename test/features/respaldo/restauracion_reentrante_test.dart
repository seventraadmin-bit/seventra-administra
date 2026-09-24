// Etapa 4B — la restauración tiene que poder interrumpirse.
//
// La auditoría 4A encontró que morir en una ventana concreta del
// arranque borraba TODOS los adjuntos: se eliminaban los vivos para
// hacer sitio, y una reentrada posterior volvía a eliminarlos, esta vez
// los ya restaurados, sin nada en espera con que reponerlos.
//
// Estas pruebas recorren cada frontera de la operación y exigen la
// propiedad que hace imposible ese final: **en ningún momento deja de
// existir un conjunto bueno completo**, porque lo que se reemplaza se
// aparta en lugar de borrarse.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:riseg_one/features/respaldo/domain/usecases/aplicar_restauracion_pendiente_usecase.dart';

void main() {
  late Directory raiz;
  late String databaseFile;
  late String attachmentsDir;
  late String restorePendingDir;
  late String restorePendingMarkerFile;
  late String restoreOldDir;

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('riseg_reentrante_');
    databaseFile = p.join(raiz.path, 'riseg_one.sqlite');
    attachmentsDir = p.join(raiz.path, 'attachments');
    restorePendingDir = p.join(raiz.path, 'restore_pending');
    restorePendingMarkerFile = p.join(raiz.path, 'restore_pending.json');
    restoreOldDir = p.join(raiz.path, 'restore_old');
  });

  tearDown(() => raiz.deleteSync(recursive: true));

  AplicarRestauracionPendienteUseCase construir() => AplicarRestauracionPendienteUseCase(
    databaseFile: databaseFile,
    attachmentsDir: attachmentsDir,
    restorePendingDir: restorePendingDir,
    restorePendingMarkerFile: restorePendingMarkerFile,
    restoreOldDir: restoreOldDir,
  );

  void crearSqlite(String ruta, {required int userVersion}) {
    Directory(p.dirname(ruta)).createSync(recursive: true);
    final db = sqlite3.open(ruta);
    db.execute('PRAGMA user_version = $userVersion');
    db.execute('CREATE TABLE IF NOT EXISTS t (id INTEGER PRIMARY KEY)');
    db.dispose();
  }

  int versionDe(String ruta) {
    final db = sqlite3.open(ruta, mode: OpenMode.readOnly);
    final v = db.userVersion;
    db.dispose();
    return v;
  }

  /// Estado inicial: una instalación con datos, y un paquete validado en
  /// espera con datos distintos.
  void prepararEscenario({required FaseRestauracion fase}) {
    crearSqlite(databaseFile, userVersion: 10);
    Directory(attachmentsDir).createSync(recursive: true);
    File(p.join(attachmentsDir, 'viejo.txt')).writeAsStringSync('viejo');

    crearSqlite(p.join(restorePendingDir, 'riseg_one.sqlite'), userVersion: 44);
    final staged = Directory(p.join(restorePendingDir, 'attachments'))..createSync(recursive: true);
    File(p.join(staged.path, 'nuevo.txt')).writeAsStringSync('nuevo');

    File(
      restorePendingMarkerFile,
    ).writeAsStringSync(jsonEncode({'preparedAt': DateTime.now().toIso8601String(), 'fase': fase.name}));
  }

  /// La propiedad central. Se comprueba en TODA frontera: nunca puede
  /// existir una base restaurada junto a unos adjuntos desaparecidos.
  void nuncaSeQuedaSinAdjuntos() {
    final vivos = Directory(attachmentsDir);
    final apartados = Directory(p.join(restoreOldDir, 'attachments'));
    final enEspera = Directory(p.join(restorePendingDir, 'attachments'));

    final hayAlgunConjunto =
        (vivos.existsSync() && vivos.listSync().isNotEmpty) ||
        (apartados.existsSync() && apartados.listSync().isNotEmpty) ||
        (enEspera.existsSync() && enEspera.listSync().isNotEmpty);

    expect(
      hayAlgunConjunto,
      isTrue,
      reason: 'en ningún punto puede desaparecer el último conjunto de adjuntos que existe',
    );
  }

  group('Reentrancia desde cada fase', () {
    for (final fase in FaseRestauracion.values) {
      test('24-30. reanudar desde la fase "${fase.name}" completa la restauración sin perder nada', () async {
        prepararEscenario(fase: fase);
        // Se simula que la fase anterior YA ocurrió, moviendo lo que esa
        // fase habría movido.
        if (fase != FaseRestauracion.preparado) {
          Directory(restoreOldDir).createSync(recursive: true);
          File(databaseFile).renameSync(p.join(restoreOldDir, 'riseg_one.sqlite'));
          File(p.join(restorePendingDir, 'riseg_one.sqlite')).renameSync(databaseFile);
        }
        if (fase == FaseRestauracion.aplicada) {
          Directory(attachmentsDir).renameSync(p.join(restoreOldDir, 'attachments'));
          Directory(p.join(restorePendingDir, 'attachments')).renameSync(attachmentsDir);
        }

        final resultado = await construir().ejecutar();

        expect(resultado, isA<RestauracionAplicadaPendienteConfirmar>());
        expect(versionDe(databaseFile), 44, reason: 'la base restaurada quedó instalada');
        expect(File(p.join(attachmentsDir, 'nuevo.txt')).existsSync(), isTrue);
        nuncaSeQuedaSinAdjuntos();
      });
    }
  });

  group('Ejecutar varias veces', () {
    test('32-33. dos y tres pasadas seguidas dejan exactamente el mismo resultado', () async {
      prepararEscenario(fase: FaseRestauracion.preparado);

      for (var i = 0; i < 3; i++) {
        final resultado = await construir().ejecutar();
        expect(resultado, isA<RestauracionAplicadaPendienteConfirmar>(), reason: 'pasada ${i + 1}');
        nuncaSeQuedaSinAdjuntos();
      }

      expect(versionDe(databaseFile), 44);
      expect(File(p.join(attachmentsDir, 'nuevo.txt')).existsSync(), isTrue);
      expect(
        File(p.join(attachmentsDir, 'viejo.txt')).existsSync(),
        isFalse,
        reason: 'los adjuntos anteriores no se mezclan con los restaurados',
      );
      expect(
        File(p.join(restoreOldDir, 'attachments', 'viejo.txt')).existsSync(),
        isTrue,
        reason: 'siguen apartados y recuperables',
      );
    });

    test('BUG DE LA AUDITORÍA 4A: reentrar justo después de instalar los adjuntos NO los borra', () async {
      prepararEscenario(fase: FaseRestauracion.preparado);
      await construir().ejecutar();
      expect(File(p.join(attachmentsDir, 'nuevo.txt')).existsSync(), isTrue);

      // Esto es exactamente lo que pasaba antes: la aplicación muere sin
      // llegar a borrar el marcador, y al volver se repite la operación.
      //
      // Se retrocede la fase a mano a propósito. Si sólo se reejecutara,
      // la fase ya escrita evitaría volver a entrar y la prueba pasaría
      // sin ejercitar la guarda que de verdad protege los adjuntos: hay
      // dos defensas independientes y ésta tiene que probar la segunda.
      File(restorePendingMarkerFile).writeAsStringSync(jsonEncode({'fase': FaseRestauracion.preparado.name}));
      await construir().ejecutar();

      expect(
        File(p.join(attachmentsDir, 'nuevo.txt')).existsSync(),
        isTrue,
        reason: 'la reentrada borraba los adjuntos recién restaurados; ya no puede',
      );
    });
  });

  group('Vuelta atrás', () {
    test('35. revertir repone la base y los adjuntos anteriores', () async {
      prepararEscenario(fase: FaseRestauracion.preparado);
      await construir().ejecutar();
      expect(versionDe(databaseFile), 44);

      final repuesto = await construir().revertir();

      expect(repuesto, isTrue);
      expect(versionDe(databaseFile), 10, reason: 'volvió la base anterior');
      expect(File(p.join(attachmentsDir, 'viejo.txt')).existsSync(), isTrue);
      expect(File(p.join(attachmentsDir, 'nuevo.txt')).existsSync(), isFalse);
      expect(File(restorePendingMarkerFile).existsSync(), isFalse);
    });

    test('revertir sin estado anterior devuelve false y no borra nada', () async {
      crearSqlite(databaseFile, userVersion: 10);

      final repuesto = await construir().revertir();

      expect(repuesto, isFalse);
      expect(versionDe(databaseFile), 10, reason: 'no se tocó lo que hay');
    });
  });

  group('Estados parciales', () {
    test('34. sin base en espera pero con marcador, no rompe ni pierde adjuntos', () async {
      crearSqlite(databaseFile, userVersion: 10);
      Directory(attachmentsDir).createSync(recursive: true);
      File(p.join(attachmentsDir, 'viejo.txt')).writeAsStringSync('viejo');
      Directory(restorePendingDir).createSync(recursive: true);
      File(restorePendingMarkerFile).writeAsStringSync(jsonEncode({'fase': FaseRestauracion.preparado.name}));

      final resultado = await construir().ejecutar();

      expect(resultado, isA<RestauracionAplicadaPendienteConfirmar>());
      expect(versionDe(databaseFile), 10, reason: 'no había base nueva: la actual sigue');
      nuncaSeQuedaSinAdjuntos();
    });

    test('un paquete sin adjuntos aparta los actuales en vez de dejarlos mezclados', () async {
      crearSqlite(databaseFile, userVersion: 10);
      Directory(attachmentsDir).createSync(recursive: true);
      File(p.join(attachmentsDir, 'viejo.txt')).writeAsStringSync('viejo');
      crearSqlite(p.join(restorePendingDir, 'riseg_one.sqlite'), userVersion: 44);
      File(restorePendingMarkerFile).writeAsStringSync(jsonEncode({'fase': FaseRestauracion.preparado.name}));

      await construir().ejecutar();

      expect(versionDe(databaseFile), 44);
      expect(File(p.join(attachmentsDir, 'viejo.txt')).existsSync(), isFalse);
      expect(
        File(p.join(restoreOldDir, 'attachments', 'viejo.txt')).existsSync(),
        isTrue,
        reason: 'apartados, no borrados: la base restaurada no los conoce, pero siguen recuperables',
      );
    });

    test('un marcador de la Etapa 14C, sin fase, se trata como recién preparado', () async {
      prepararEscenario(fase: FaseRestauracion.preparado);
      File(restorePendingMarkerFile).writeAsStringSync(jsonEncode({'preparedAt': '2026-01-01T00:00:00.000'}));

      final resultado = await construir().ejecutar();

      expect(resultado, isA<RestauracionAplicadaPendienteConfirmar>());
      expect(versionDe(databaseFile), 44);
    });
  });

  test('31. el marcador sobrevive al éxito material, y sólo confirmar lo retira', () async {
    prepararEscenario(fase: FaseRestauracion.preparado);

    await construir().ejecutar();
    expect(File(restorePendingMarkerFile).existsSync(), isTrue);

    await construir().confirmar();
    expect(File(restorePendingMarkerFile).existsSync(), isFalse);
    expect(Directory(restoreOldDir).existsSync(), isFalse);
  });
}
