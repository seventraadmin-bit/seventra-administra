// Etapa 4B (cierre) — "abrió" no es "aceptada".
//
// Confirmar una restauración es el único momento en que RISEG ONE
// destruye el estado anterior: `restore_old` es el último ejemplar de
// los datos que el usuario tenía hace un minuto. Hasta esta pasada
// bastaba con que Drift lograra abrir el archivo para borrarlo, y esa
// vara es demasiado baja — un respaldo de un esquema viejo puede abrir,
// fallar a mitad de su migración y dejar la aplicación operando sobre
// algo que ya nadie puede reponer.
//
// Estas pruebas recorren las tres salidas: migración que no llega,
// validación posterior que no pasa, y el camino feliz.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:riseg_one/app/apertura_base_restaurada.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/logging/app_logger.dart';
import 'package:riseg_one/features/respaldo/domain/usecases/aplicar_restauracion_pendiente_usecase.dart';

/// No imprime nada durante las pruebas, pero deja ver qué se registró:
/// que un fallo quede dicho es parte del comportamiento, no un adorno.
class _LoggerEnMemoria implements AppLogger {
  final errores = <String>[];
  final infos = <String>[];

  @override
  void info(String mensaje) => infos.add(mensaje);

  @override
  void error(String mensaje, [Object? error, StackTrace? stack]) => errores.add('$mensaje | $error');

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late Directory raiz;
  late String databaseFile;
  late String attachmentsDir;
  late String restorePendingDir;
  late String restorePendingMarkerFile;
  late String restoreOldDir;
  late _LoggerEnMemoria logger;

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('riseg_confirmar_');
    databaseFile = p.join(raiz.path, 'riseg_one.sqlite');
    attachmentsDir = p.join(raiz.path, 'attachments');
    restorePendingDir = p.join(raiz.path, 'restore_pending');
    restorePendingMarkerFile = p.join(raiz.path, 'restore_pending.json');
    restoreOldDir = p.join(raiz.path, 'restore_old');
    logger = _LoggerEnMemoria();
  });

  tearDown(() {
    try {
      raiz.deleteSync(recursive: true);
    } on FileSystemException {
      // En Windows el archivo puede seguir tomado un instante después
      // de cerrar; no es lo que se está probando.
    }
  });

  AplicarRestauracionPendienteUseCase restaurador() => AplicarRestauracionPendienteUseCase(
    databaseFile: databaseFile,
    attachmentsDir: attachmentsDir,
    restorePendingDir: restorePendingDir,
    restorePendingMarkerFile: restorePendingMarkerFile,
    restoreOldDir: restoreOldDir,
  );

  /// Una base REAL de esta build: se crea con Drift, así que tiene el
  /// esquema completo y su `user_version` es la de hoy.
  Future<void> crearBaseRealEn(String ruta) async {
    final db = AppDatabase(openAppDatabaseConnection(ruta));
    await db.customSelect('SELECT 1').get();
    await db.close();
  }

  /// Una base que pretende ser de una versión anterior pero no tiene su
  /// estructura — exactamente lo que ocurre cuando un respaldo viejo ya
  /// no puede llegar al esquema de hoy: la migración lanza.
  void crearBaseQueNoPuedeMigrar(String ruta, {required int userVersion}) {
    Directory(p.dirname(ruta)).createSync(recursive: true);
    final db = sqlite3.open(ruta);
    db.execute('PRAGMA user_version = $userVersion');
    db.execute('CREATE TABLE app_metadata (id INTEGER PRIMARY KEY)');
    db.dispose();
  }

  /// Una base que abre sin migrar (ya viene en la versión de hoy) pero
  /// cuyos datos se contradicen: `foreign_key_check` la delata.
  void crearBaseConReferenciaRota(String ruta, {required int userVersion}) {
    Directory(p.dirname(ruta)).createSync(recursive: true);
    final db = sqlite3.open(ruta);
    db.execute('PRAGMA user_version = $userVersion');
    db.execute('CREATE TABLE padre (id INTEGER PRIMARY KEY)');
    db.execute('CREATE TABLE hijo (id INTEGER PRIMARY KEY, padre_id INTEGER REFERENCES padre(id))');
    db.execute('INSERT INTO hijo (id, padre_id) VALUES (1, 999)');
    db.dispose();
  }

  int versionDe(String ruta) {
    final db = sqlite3.open(ruta, mode: OpenMode.readOnly);
    final v = db.userVersion;
    db.dispose();
    return v;
  }

  /// Deja el escenario tal como lo encontraría el arranque: una base
  /// anterior apartada, adjuntos anteriores apartados, y la nueva ya
  /// instalada. Es lo que `AplicarRestauracionPendienteUseCase` produce.
  Future<void> instalarComoRestauracionAplicada({
    required void Function(String ruta) crearNueva,
    int adjuntosRestaurados = 1,
  }) async {
    // Estado anterior, que es lo que debe poder volver.
    await crearBaseRealEn(p.join(restoreOldDir, 'riseg_one.sqlite'));
    final anteriores = Directory(p.join(restoreOldDir, 'attachments'))..createSync(recursive: true);
    File(p.join(anteriores.path, 'contrato_viejo.pdf')).writeAsStringSync('documento anterior');

    // Lo restaurado, ya en su sitio.
    crearNueva(databaseFile);
    final vivos = Directory(attachmentsDir)..createSync(recursive: true);
    var bytes = 0;
    for (var i = 0; i < adjuntosRestaurados; i++) {
      final contenido = 'documento restaurado $i';
      File(p.join(vivos.path, 'nuevo_$i.pdf')).writeAsStringSync(contenido);
      bytes += contenido.length;
    }

    File(restorePendingMarkerFile).writeAsStringSync(
      jsonEncode({
        'preparedAt': DateTime.now().toIso8601String(),
        'fase': FaseRestauracion.aplicada.name,
        campoAdjuntosEsperados: adjuntosRestaurados,
        campoBytesAdjuntosEsperados: bytes,
      }),
    );
    Directory(restorePendingDir).createSync(recursive: true);
  }

  void esperarEstadoAnteriorRepuesto() {
    expect(
      File(p.join(attachmentsDir, 'contrato_viejo.pdf')).existsSync(),
      isTrue,
      reason: 'volvieron los adjuntos de antes',
    );
    expect(File(p.join(attachmentsDir, 'nuevo_0.pdf')).existsSync(), isFalse);
    expect(File(restorePendingMarkerFile).existsSync(), isFalse, reason: 'ya no hay restauración pendiente');
    expect(Directory(restoreOldDir).existsSync(), isFalse, reason: 'el apartado se consumió al reponerlo');
  }

  group('Migración que no llega', () {
    test('un respaldo viejo que no puede migrar NO se confirma y deja RISEG ONE en pie', () async {
      await instalarComoRestauracionAplicada(crearNueva: (ruta) => crearBaseQueNoPuedeMigrar(ruta, userVersion: 91));

      final apertura = await abrirConfirmandoRestauracion(
        databaseFile: databaseFile,
        restaurador: restaurador(),
        logger: logger,
      );
      await apertura.database.close();

      expect(apertura.confirmada, isFalse);
      expect(apertura.motivo, MotivoRestauracionNoConfirmada.noAbreOMigracionFallida);
      expect(apertura.estadoAnteriorRepuesto, isTrue);
      expect(
        versionDe(databaseFile),
        92,
        reason: 'la base que quedó es la anterior, completa — no el intento a medio migrar',
      );
      esperarEstadoAnteriorRepuesto();
      expect(logger.errores, isNotEmpty, reason: 'un fallo así no puede ocurrir en silencio');
    });

    test('y la aplicación sigue usable: la base repuesta abre y responde', () async {
      await instalarComoRestauracionAplicada(crearNueva: (ruta) => crearBaseQueNoPuedeMigrar(ruta, userVersion: 91));

      final apertura = await abrirConfirmandoRestauracion(
        databaseFile: databaseFile,
        restaurador: restaurador(),
        logger: logger,
      );

      // Ésta es la propiedad que importa: restaurar un respaldo viejo
      // que no puede migrar no deja a RISEG ONE muerto.
      final filas = await apertura.database.customSelect('SELECT 1 AS uno').get();
      expect(filas.single.data['uno'], 1);
      await apertura.database.close();
    });
  });

  group('Validación posterior que no pasa', () {
    test('abre y no migra, pero foreign_key_check la delata: no se confirma, se revierte', () async {
      await instalarComoRestauracionAplicada(
        // Ya viene en la versión de hoy, así que Drift no migra nada:
        // abre sin una sola queja. Sólo la comprobación posterior puede
        // notar que sus datos se contradicen.
        crearNueva: (ruta) => crearBaseConReferenciaRota(ruta, userVersion: 92),
      );

      final apertura = await abrirConfirmandoRestauracion(
        databaseFile: databaseFile,
        restaurador: restaurador(),
        logger: logger,
      );
      await apertura.database.close();

      expect(apertura.motivo, MotivoRestauracionNoConfirmada.referencias, reason: '"abrir" no equivale a "confirmar"');
      expect(apertura.estadoAnteriorRepuesto, isTrue);
      esperarEstadoAnteriorRepuesto();
    });

    test('una base marcada con una versión más nueva tampoco se confirma', () async {
      // Este caso no llega siquiera a la comprobación de versión: Drift
      // no degrada un esquema, así que la apertura falla antes. Se deja
      // la prueba porque lo que importa es la consecuencia —no se
      // confirma y vuelve lo anterior—, no qué comprobación lo atrapó.
      //
      // La comprobación `user_version == schemaVersion` que sí existe
      // en `abrirConfirmandoRestauracion` es deliberadamente redundante:
      // hoy Drift la deja siempre en su sitio tras migrar, y el día que
      // deje de hacerlo esto no pasará inadvertido.
      await instalarComoRestauracionAplicada(crearNueva: (ruta) => crearBaseConReferenciaRota(ruta, userVersion: 93));

      final apertura = await abrirConfirmandoRestauracion(
        databaseFile: databaseFile,
        restaurador: restaurador(),
        logger: logger,
      );
      await apertura.database.close();

      expect(apertura.confirmada, isFalse);
      expect(apertura.estadoAnteriorRepuesto, isTrue);
      esperarEstadoAnteriorRepuesto();
    });

    test('adjuntos que no son los validados: no se confirma, se revierte', () async {
      await instalarComoRestauracionAplicada(crearNueva: (_) {}, adjuntosRestaurados: 2);
      await crearBaseRealEn(databaseFile);
      // Uno de los dos desapareció mientras la aplicación estuvo
      // cerrada: cuarentena del antivirus, sincronización a medias.
      File(p.join(attachmentsDir, 'nuevo_1.pdf')).deleteSync();

      final apertura = await abrirConfirmandoRestauracion(
        databaseFile: databaseFile,
        restaurador: restaurador(),
        logger: logger,
      );
      await apertura.database.close();

      expect(apertura.motivo, MotivoRestauracionNoConfirmada.adjuntos);
      expect(apertura.estadoAnteriorRepuesto, isTrue);
      esperarEstadoAnteriorRepuesto();
    });

    test('un marcador sin expectativa de adjuntos no inventa una discrepancia', () async {
      await instalarComoRestauracionAplicada(crearNueva: (_) {});
      await crearBaseRealEn(databaseFile);
      // Marcador de la Etapa 14C: no declara nada sobre adjuntos.
      File(restorePendingMarkerFile).writeAsStringSync(jsonEncode({'fase': FaseRestauracion.aplicada.name}));

      final apertura = await abrirConfirmandoRestauracion(
        databaseFile: databaseFile,
        restaurador: restaurador(),
        logger: logger,
      );
      await apertura.database.close();

      expect(apertura.confirmada, isTrue, reason: 'no saber qué esperar no es lo mismo que estar mal');
    });
  });

  group('Confirmación feliz', () {
    test('base real, migrada, íntegra y con sus adjuntos: se confirma y se suelta el estado anterior', () async {
      await instalarComoRestauracionAplicada(crearNueva: (_) {});
      await crearBaseRealEn(databaseFile);

      final apertura = await abrirConfirmandoRestauracion(
        databaseFile: databaseFile,
        restaurador: restaurador(),
        logger: logger,
      );

      expect(apertura.confirmada, isTrue);
      expect(apertura.motivo, isNull);
      expect(versionDe(databaseFile), 92);
      expect(File(p.join(attachmentsDir, 'nuevo_0.pdf')).existsSync(), isTrue, reason: 'quedaron los restaurados');
      expect(Directory(restoreOldDir).existsSync(), isFalse, reason: 'recién AHORA se suelta el estado anterior');
      expect(Directory(restorePendingDir).existsSync(), isFalse);
      expect(File(restorePendingMarkerFile).existsSync(), isFalse);
      expect(logger.errores, isEmpty);

      await apertura.database.close();
    });

    test('el estado anterior sigue intacto hasta el instante en que se confirma', () async {
      await instalarComoRestauracionAplicada(crearNueva: (_) {});
      await crearBaseRealEn(databaseFile);

      // Antes de abrir: todo lo anterior sigue ahí.
      expect(File(p.join(restoreOldDir, 'riseg_one.sqlite')).existsSync(), isTrue);
      expect(File(p.join(restoreOldDir, 'attachments', 'contrato_viejo.pdf')).existsSync(), isTrue);

      final apertura = await abrirConfirmandoRestauracion(
        databaseFile: databaseFile,
        restaurador: restaurador(),
        logger: logger,
      );
      await apertura.database.close();

      expect(Directory(restoreOldDir).existsSync(), isFalse);
    });
  });
}
