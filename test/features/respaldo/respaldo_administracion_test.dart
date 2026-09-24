// Etapa 4B — la lista de respaldos deja de ser decorativa.
//
// Antes mostraba nombre, fecha y tamaño, y no se podía hacer nada con
// ella: ni restaurar, ni verificar, ni borrar, ni abrir la carpeta.
// Había que volver a buscar el archivo con el explorador.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/config/app_paths.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/permissions/modulos_permiso.dart';
import 'package:riseg_one/features/respaldo/domain/abridor_ubicacion.dart';
import 'package:riseg_one/features/respaldo/domain/manifest_respaldo.dart';
import 'package:riseg_one/features/respaldo/domain/usecases/crear_respaldo_usecase.dart';
import 'package:riseg_one/features/respaldo/domain/usecases/eliminar_respaldo_usecase.dart';
import 'package:riseg_one/features/respaldo/presentation/respaldo_controller.dart';
import 'package:riseg_one/features/respaldo/presentation/respaldo_screen.dart';
import 'package:riseg_one/features/respaldo/presentation/respaldo_state.dart';
import 'package:riseg_one/features/respaldo/respaldo_providers.dart';
import 'package:riseg_one/features/respaldo/domain/usecases/preparar_restauracion_usecase.dart';
import 'package:riseg_one/features/respaldo/domain/usecases/validar_paquete_respaldo_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import '../../support/sesion_en_base.dart';

const _sesionMaestro = SesionUsuario(
  usuarioId: 'usuario-maestro',
  nombre: 'MARLON',
  nombreUsuario: 'marlon',
  esMaestro: true,
  permisos: {},
);

const _sesionNormal = SesionUsuario(
  usuarioId: 'usuario-normal',
  nombre: 'JAVIER',
  nombreUsuario: 'javier',
  esMaestro: false,
  // El permiso más fuerte que un Normal puede tener: sigue sin bastar.
  permisos: {'usuarios.administrar'},
);

class _SesionFija extends SesionController {
  _SesionFija(this._sesion);
  final SesionUsuario _sesion;

  @override
  SesionUsuario? build() => _sesion;
}

/// `AppPaths` no se puede construir sin `path_provider`, así que las
/// rutas se sobreescriben una por una — igual que hace el resto del
/// proyecto con las fronteras del sistema operativo.
class _PathsDePrueba implements AppPaths {
  _PathsDePrueba(this._raiz);
  final String _raiz;

  @override
  String get rootDir => _raiz;
  @override
  String get databaseFile => p.join(_raiz, 'riseg_one.sqlite');
  @override
  String get attachmentsDir => p.join(_raiz, 'attachments');
  @override
  String get backupsDir => p.join(_raiz, 'backups');
  @override
  String get reportesDir => p.join(_raiz, 'reportes');
  @override
  String get recibosDir => p.join(_raiz, 'recibos');
  @override
  String get nominaDispersionDir => p.join(_raiz, 'nomina_dispersion');
  @override
  String get datosFiscalesDir => p.join(_raiz, 'datos_fiscales');
  @override
  String get restorePendingDir => p.join(_raiz, 'restore_pending');
  @override
  String get restorePendingMarkerFile => p.join(_raiz, 'restore_pending.json');
  @override
  String get restoreOldDir => p.join(_raiz, 'restore_old');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// No se lanza el Explorador en una prueba: se comprueba con qué ruta
/// se le habría llamado, que es lo único que puede estar mal aquí.
class _AbridorEspia implements AbridorUbicacion {
  final rutas = <String>[];

  @override
  Future<bool> mostrarArchivo(String ruta) async {
    rutas.add(ruta);
    return true;
  }
}

void main() {
  late Directory raiz;
  late AppDatabase db;
  late _PathsDePrueba paths;

  setUp(() async {
    raiz = Directory.systemTemp.createTempSync('riseg_admin_');
    paths = _PathsDePrueba(raiz.path);
    db = AppDatabase(NativeDatabase.memory());

    final real = sqlite3.open(paths.databaseFile);
    real.execute('PRAGMA user_version = 92');
    real.execute('CREATE TABLE t (id INTEGER PRIMARY KEY)');
    real.dispose();

    Directory(paths.attachmentsDir).createSync(recursive: true);
    File(p.join(paths.attachmentsDir, 'foto.jpg')).writeAsStringSync('foto');
    Directory(paths.backupsDir).createSync(recursive: true);
  });

  tearDown(() {
    db.close();
    raiz.deleteSync(recursive: true);
  });

  Future<ProviderContainer> contenedor({SesionUsuario sesion = _sesionMaestro, AbridorUbicacion? abridor}) async {
    await sembrarSesionEnBase(db, sesion);
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        appPathsProvider.overrideWithValue(paths),
        sesionControllerProvider.overrideWith(() => _SesionFija(sesion)),
        if (abridor != null) abridorUbicacionProvider.overrideWithValue(abridor),
      ],
    );
    addTearDown(c.dispose);
    // El controlador es autoDispose: sin un oyente vivo se reconstruiría
    // entre lecturas y la lista recién cargada volvería a quedar vacía.
    c.listen(respaldoControllerProvider, (_, _) {});
    return c;
  }

  Future<String> crearRespaldoEn(String nombre, {TipoRespaldo tipo = TipoRespaldo.manual}) async {
    final destino = p.join(paths.backupsDir, nombre);
    final r = await CrearRespaldoUseCase(
      databaseFile: paths.databaseFile,
      attachmentsDir: paths.attachmentsDir,
    ).ejecutar(destinoZip: destino, tipo: tipo);
    expect(r, isA<RespaldoCreado>());
    return destino;
  }

  group('51-52. La lista', () {
    test('51. muestra los respaldos de la carpeta, con su tipo y su formato', () async {
      await crearRespaldoEn('manual.zip');
      await crearRespaldoEn('pre-restore-x.zip', tipo: TipoRespaldo.preventivo);
      final c = await contenedor();

      await c.read(respaldoControllerProvider.notifier).recargar();
      final state = c.read(respaldoControllerProvider);

      expect(state.respaldos, hasLength(2));
      expect(state.respaldos.map((r) => r.tipo), containsAll([TipoRespaldo.manual, TipoRespaldo.preventivo]));
      expect(state.respaldos.every((r) => r.appSchemaVersion == 92), isTrue);
      expect(
        state.respaldos.every((r) => r.integridad == EstadoIntegridad.sinVerificar),
        isTrue,
        reason: 'listar no verifica: abrir y hashear cada .zip al pintar sería absurdo',
      );
    });

    test('52. un respaldo guardado FUERA de la carpeta no aparece', () async {
      final fuera = Directory(p.join(raiz.path, 'usb'))..createSync();
      await CrearRespaldoUseCase(
        databaseFile: paths.databaseFile,
        attachmentsDir: paths.attachmentsDir,
      ).ejecutar(destinoZip: p.join(fuera.path, 'externo.zip'));
      final c = await contenedor();

      await c.read(respaldoControllerProvider.notifier).recargar();

      expect(
        c.read(respaldoControllerProvider).respaldos,
        isEmpty,
        reason: 'la lista es lo que hay en una carpeta, no un historial de respaldos conocidos',
      );
    });

    test('un .zip que no es un respaldo se marca como dañado sin romper la lista', () async {
      File(p.join(paths.backupsDir, 'cualquiera.zip')).writeAsStringSync('no soy un zip');
      final c = await contenedor();

      await c.read(respaldoControllerProvider.notifier).recargar();

      final fila = c.read(respaldoControllerProvider).respaldos.single;
      expect(fila.integridad, EstadoIntegridad.invalido);
      expect(fila.tipo, isNull);
    });
  });

  group('53-60. Acciones', () {
    test('58-59. verificar usa el validador canónico y recuerda el resultado', () async {
      final ruta = await crearRespaldoEn('manual.zip');
      final c = await contenedor();
      await c.read(respaldoControllerProvider.notifier).recargar();

      final archivo = c.read(respaldoControllerProvider).respaldos.single;
      await c.read(respaldoControllerProvider.notifier).verificar(archivo);

      expect(c.read(respaldoControllerProvider).respaldos.single.integridad, EstadoIntegridad.verificado);
      expect(File(ruta).existsSync(), isTrue, reason: 'verificar no altera el archivo');
    });

    test('59. un respaldo corrupto se verifica como inválido', () async {
      final ruta = await crearRespaldoEn('manual.zip');
      await File(ruta).writeAsString('ya no es un zip');
      final c = await contenedor();
      await c.read(respaldoControllerProvider.notifier).recargar();

      final archivo = c.read(respaldoControllerProvider).respaldos.single;
      await c.read(respaldoControllerProvider.notifier).verificar(archivo);

      expect(c.read(respaldoControllerProvider).respaldos.single.integridad, EstadoIntegridad.invalido);
    });

    test('56. eliminar borra SÓLO ese .zip', () async {
      await crearRespaldoEn('uno.zip');
      await crearRespaldoEn('dos.zip');
      final c = await contenedor();
      await c.read(respaldoControllerProvider.notifier).recargar();

      final aBorrar = c.read(respaldoControllerProvider).respaldos.firstWhere((r) => r.nombre == 'uno.zip');
      final resultado = await c.read(respaldoControllerProvider.notifier).eliminar(aBorrar);

      expect(resultado, isA<RespaldoEliminado>());
      expect(File(p.join(paths.backupsDir, 'uno.zip')).existsSync(), isFalse);
      expect(File(p.join(paths.backupsDir, 'dos.zip')).existsSync(), isTrue);
      expect(File(paths.databaseFile).existsSync(), isTrue, reason: 'la base no se toca');
      expect(File(p.join(paths.attachmentsDir, 'foto.jpg')).existsSync(), isTrue, reason: 'los adjuntos tampoco');
    });

    test('55. eliminar exige Maestro: ni siquiera usuarios.administrar alcanza', () async {
      await crearRespaldoEn('uno.zip');
      final c = await contenedor(sesion: _sesionNormal);
      await c.read(respaldoControllerProvider.notifier).recargar();

      final archivo = c.read(respaldoControllerProvider).respaldos.single;
      final resultado = await c.read(respaldoControllerProvider.notifier).eliminar(archivo);

      expect(resultado, isA<EliminarRespaldoErrorInesperado>());
      expect(File(p.join(paths.backupsDir, 'uno.zip')).existsSync(), isTrue);
    });

    test('41. un preventivo no puede borrarse mientras su restauración siga pendiente', () async {
      await crearRespaldoEn('pre-restore-x.zip', tipo: TipoRespaldo.preventivo);
      File(paths.restorePendingMarkerFile).writeAsStringSync('{"fase":"preparado"}');
      final c = await contenedor();
      await c.read(respaldoControllerProvider.notifier).recargar();

      final archivo = c.read(respaldoControllerProvider).respaldos.single;
      final resultado = await c.read(respaldoControllerProvider.notifier).eliminar(archivo);

      expect(resultado, isA<RespaldoProtegidoPorRestauracionPendiente>());
      expect(File(p.join(paths.backupsDir, 'pre-restore-x.zip')).existsSync(), isTrue);
    });

    test('sin restauración pendiente, un preventivo sí puede borrarse', () async {
      await crearRespaldoEn('pre-restore-x.zip', tipo: TipoRespaldo.preventivo);
      final c = await contenedor();
      await c.read(respaldoControllerProvider.notifier).recargar();

      final archivo = c.read(respaldoControllerProvider).respaldos.single;

      expect(await c.read(respaldoControllerProvider.notifier).eliminar(archivo), isA<RespaldoEliminado>());
    });

    test('53. restaurar desde un archivo EXTERNO a la carpeta funciona', () async {
      final fuera = Directory(p.join(raiz.path, 'usb'))..createSync();
      final externo = p.join(fuera.path, 'externo.zip');
      await CrearRespaldoUseCase(
        databaseFile: paths.databaseFile,
        attachmentsDir: paths.attachmentsDir,
      ).ejecutar(destinoZip: externo);
      final c = await contenedor();

      final resultado = await c.read(respaldoControllerProvider.notifier).restaurar(externo);

      expect(resultado, isA<RestauracionPreparada>());
      expect(File(paths.restorePendingMarkerFile).existsSync(), isTrue);
    });

    test('37-39. la restauración crea antes su preventivo, marcado como tal', () async {
      final origen = await crearRespaldoEn('manual.zip');
      final c = await contenedor();

      await c.read(respaldoControllerProvider.notifier).restaurar(origen);
      await c.read(respaldoControllerProvider.notifier).recargar();

      final preventivos = c.read(respaldoControllerProvider).respaldos.where((r) => r.tipo == TipoRespaldo.preventivo);
      expect(preventivos, hasLength(1), reason: 'se creó exactamente uno');
      expect(preventivos.single.nombre, startsWith('pre-restore-'));
    });

    test('57. abrir ubicación señala ESE archivo, no la carpeta ni otra fila', () async {
      await crearRespaldoEn('uno.zip');
      await crearRespaldoEn('dos.zip');
      final espia = _AbridorEspia();
      final c = await contenedor(abridor: espia);
      await c.read(respaldoControllerProvider.notifier).recargar();

      final elegido = c.read(respaldoControllerProvider).respaldos.firstWhere((r) => r.nombre == 'dos.zip');
      await c.read(respaldoControllerProvider.notifier).abrirUbicacion(elegido);

      expect(espia.rutas, [p.join(paths.backupsDir, 'dos.zip')]);
    });

    test('60. un paquete v1 se verifica como LIMITADA, nunca como verificado', () async {
      final zipV1 = p.join(paths.backupsDir, 'antiguo_v1.zip');
      final encoder = ZipFileEncoder();
      encoder.create(zipV1);
      await encoder.addFile(File(paths.databaseFile), 'riseg_one.sqlite');
      await encoder.addFile(File(p.join(paths.attachmentsDir, 'foto.jpg')), 'attachments/foto.jpg');
      final manifiesto = utf8.encode(
        jsonEncode({
          'formatVersion': 1,
          'createdAt': DateTime(2026, 1, 1).toIso8601String(),
          'appSchemaVersion': 44,
          'integridadVerificada': true,
          'archivosAdjuntos': 1,
          'bytesAdjuntos': 4,
        }),
      );
      encoder.addArchiveFile(ArchiveFile('manifest.json', manifiesto.length, manifiesto));
      await encoder.close();

      final c = await contenedor();
      await c.read(respaldoControllerProvider.notifier).recargar();
      final fila = c.read(respaldoControllerProvider).respaldos.single;
      expect(fila.esFormatoAnterior, isTrue, reason: 'la lista lo distingue antes incluso de verificarlo');

      await c.read(respaldoControllerProvider.notifier).verificar(fila);

      expect(
        c.read(respaldoControllerProvider).respaldos.single.integridad,
        EstadoIntegridad.limitada,
        reason: 'ese formato no guarda huellas de adjuntos: decir "verificado" sería mentir',
      );
    });

    test('38. si el preventivo falla, NO queda restauración pendiente', () async {
      final origen = await crearRespaldoEn('manual.zip');
      // El preventivo no puede salir: la base que tendría que copiar ya
      // no está donde se le dijo.
      final caso = PrepararRestauracionUseCase(
        backupsDir: paths.backupsDir,
        restorePendingDir: paths.restorePendingDir,
        restorePendingMarkerFile: paths.restorePendingMarkerFile,
        validar: ValidarPaqueteRespaldoUseCase(),
        crearRespaldo: CrearRespaldoUseCase(
          databaseFile: p.join(raiz.path, 'no_existe.sqlite'),
          attachmentsDir: paths.attachmentsDir,
        ),
      );

      final resultado = await caso.ejecutar(rutaZip: origen, appSchemaVersionActual: 92);

      expect(resultado, isA<RestauracionRespaldoPreventivoFallido>());
      expect(
        File(paths.restorePendingMarkerFile).existsSync(),
        isFalse,
        reason: 'sin red de seguridad no se arranca la operación: el reinicio no debe restaurar nada',
      );
      expect(Directory(paths.restorePendingDir).existsSync(), isFalse);
      expect(File(paths.databaseFile).existsSync(), isTrue, reason: 'los datos actuales siguen intactos');
    });
  });

  group('Pantalla', () {
    /// Todo el montaje de datos ocurre en `runAsync`: crear un `.zip` y
    /// leer su manifiesto es E/S real, que no avanza bajo el reloj falso
    /// de `pumpAndSettle`. Si se dejara dentro, la lista quedaría
    /// cargando para siempre.
    Future<ProviderContainer> preparar(
      WidgetTester tester,
      double ancho, {
      List<String> respaldos = const [],
      SesionUsuario sesion = _sesionMaestro,
    }) async {
      late ProviderContainer c;
      await tester.runAsync(() async {
        for (final nombre in respaldos) {
          await crearRespaldoEn(
            nombre,
            tipo: nombre.startsWith('pre-restore-') ? TipoRespaldo.preventivo : TipoRespaldo.manual,
          );
        }
        c = await contenedor(sesion: sesion);
        await c.read(respaldoControllerProvider.notifier).recargar();
      });

      tester.view.physicalSize = Size(ancho, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: RespaldoScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('el aviso nombra Bóveda, Telefonía y Portal — no sólo Telefonía', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await preparar(tester, 1366);

      expect(find.byKey(const Key('respaldo_aviso_credenciales')), findsOneWidget);
      final mensaje = l10n.respaldoAvisoCredencialesMensaje;
      expect(mensaje, contains('Bóveda'));
      expect(mensaje, contains('Telefonía'));
      expect(mensaje, contains('Portal'));
      expect(
        l10n.respaldoDescripcion,
        isNot(contains('credenciales')),
        reason: 'la advertencia vive en su propio bloque, no perdida al final de un párrafo',
      );
    });

    testWidgets('54. el menú ⋮ ofrece las cuatro acciones', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await preparar(tester, 1366, respaldos: ['manual.zip']);

      await tester.tap(find.byKey(const Key('respaldo_menu_manual.zip')));
      await tester.pumpAndSettle();

      for (final etiqueta in [
        l10n.respaldoAccionRestaurar,
        l10n.respaldoAccionVerificar,
        l10n.respaldoAccionAbrirUbicacion,
        l10n.respaldoAccionEliminar,
      ]) {
        expect(find.text(etiqueta), findsOneWidget, reason: 'falta "$etiqueta"');
      }
    });

    testWidgets('54. pulsar ⋮ abre el menú y nada más: la fila no tiene acción propia', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      final c = await preparar(tester, 1366, respaldos: ['manual.zip']);

      await tester.tap(find.byKey(const Key('respaldo_menu_manual.zip')));
      await tester.pumpAndSettle();

      // Si la tarjeta llevara su propio `onTap`, el toque habría llegado
      // también a ella y estaríamos viendo una confirmación encima del
      // menú — o peor, una restauración ya en marcha.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(l10n.respaldoRestaurarConfirmarTitulo), findsNothing);
      expect(c.read(respaldoControllerProvider).procesando, isFalse);
      expect(File(paths.restorePendingMarkerFile).existsSync(), isFalse);
      expect(File(p.join(paths.backupsDir, 'manual.zip')).existsSync(), isTrue);
    });

    testWidgets('la lista se llama "Respaldos en este equipo", nunca "Historial"', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await preparar(tester, 1366);

      expect(find.text(l10n.respaldoListaLocalTitulo), findsOneWidget);
      expect(find.textContaining('Historial'), findsNothing);
    });

    for (final ancho in [1366.0, 1024.0, 700.0, 500.0]) {
      final etiqueta = ancho.toInt();

      testWidgets('responsive a ${etiqueta}px: cero overflow con respaldos y aviso', (tester) async {
        await preparar(
          tester,
          ancho,
          respaldos: ['un_nombre_de_respaldo_bastante_largo_20260923.zip', 'pre-restore-2026-09-23T10-00-00-000.zip'],
        );

        expect(tester.takeException(), isNull);
      });

      testWidgets('menú ⋮ a ${etiqueta}px se abre dentro del viewport', (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('es'));
        await preparar(tester, ancho, respaldos: ['manual.zip']);

        // A 700 px y menos la cabecera explicativa ya no cabe entera, así
        // que la fila queda debajo del borde y hay que desplazarse hasta
        // ella — que es exactamente lo que hace una persona.
        final menu = find.byKey(const Key('respaldo_menu_manual.zip'));
        await tester.scrollUntilVisible(menu, 120, scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        await tester.tap(menu);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final caja = tester.getRect(find.text(l10n.respaldoAccionEliminar));
        expect(caja.left, greaterThanOrEqualTo(0));
        expect(caja.right, lessThanOrEqualTo(ancho));
        expect(caja.bottom, lessThanOrEqualTo(768));
      });
    }
  });

  test('el catálogo de permisos sigue sin exponer Respaldo: es Maestro-only', () {
    expect(
      todosLosCodigosDePermiso().where((c) => c.startsWith('respaldo')),
      isEmpty,
      reason: 'ningún permiso dinámico puede alcanzar esta pantalla',
    );
  });
}
