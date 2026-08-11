// Pruebas de la pantalla de listado de Áreas — alta/edición vía el
// mismo diálogo, y el bloqueo de desactivar cuando el Área tiene
// Puestos activos (deliverable #4 de la Etapa 4D: la regla se aplica
// siempre, sin excepción — ver `DesactivarAreaUseCase`).

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/area_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_puesto_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/puesto_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/areas/areas_list_screen.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

/// Sesión Maestro fija — Etapa 11C activó autorización real en las
/// acciones de este diálogo; sin este override todas serían rechazadas
/// por `AuthorizationService` (mismo criterio que `smoke_test.dart`).
class _SesionControllerDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-prueba',
      nombre: 'Usuario de prueba',
      nombreUsuario: 'prueba',
      esMaestro: true,
      permisos: {},
    );
  }
}

Future<void> _pumpScreen(WidgetTester tester, AppDatabase db) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionControllerDePrueba.new),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AreasListScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  testWidgets('muestra las Áreas sembradas', (tester) async {
    await _pumpScreen(tester, db);

    expect(find.text('Operaciones'), findsOneWidget);
    expect(find.text('Reclutamiento'), findsOneWidget);
  });

  testWidgets('crear una nueva Área vía el diálogo de alta', (tester) async {
    await _pumpScreen(tester, db);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('areas_boton_nueva')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Tecnología');
    await tester.tap(find.text(l10n.areaDialogoBotonGuardar));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Tecnología'), findsOneWidget);
  });

  testWidgets('editar una Área existente vía el mismo diálogo', (tester) async {
    await _pumpScreen(tester, db);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.widgetWithIcon(IconButton, Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    expect(find.text(l10n.areaDialogoTituloEdicion), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Operaciones Renombrada');
    await tester.tap(find.text(l10n.areaDialogoBotonGuardar));
    await tester.pumpAndSettle();

    expect(find.text('Operaciones Renombrada'), findsOneWidget);
  });

  testWidgets(
    'desactivar un Área con Puestos activos se bloquea con un error, sin ningún diálogo de éxito',
    (tester) async {
      final crearPuesto = CrearPuestoUseCase(
        PuestoRepositoryImpl(db),
        GenerarCodigoUseCase(CodigoSecuenciaService(db)),
        PuestoValidator(AreaRepositoryImpl(db)),
      );
      await crearPuesto.ejecutar(const PuestoBorrador(
        nombre: 'Guardia',
        areaId: SeedIds.areaOperaciones,
        tipo: TipoPuesto.operativo,
        nivelJerarquico: 1,
      ));

      await _pumpScreen(tester, db);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.tap(find.widgetWithIcon(IconButton, Icons.toggle_on_outlined).first);
      await tester.pumpAndSettle();
      expect(find.text(l10n.areaConfirmarDesactivarTitulo), findsOneWidget);

      await tester.tap(find.text(l10n.sucursalConfirmarAceptar));
      await tester.pumpAndSettle();

      expect(find.text(l10n.areaDesactivarBloqueadaError(1)), findsOneWidget);
      // Sigue Activo — el bloqueo no debe haber modificado el registro.
      expect(find.text(l10n.areaEstadoActivo), findsWidgets);
    },
  );

  testWidgets('desactivar un Área sin Puestos activos funciona tras confirmar', (tester) async {
    await _pumpScreen(tester, db);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.widgetWithIcon(IconButton, Icons.toggle_on_outlined).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.sucursalConfirmarAceptar));
    await tester.pumpAndSettle();

    expect(find.widgetWithIcon(IconButton, Icons.toggle_off_outlined), findsOneWidget);
  });
}
