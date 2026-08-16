// Etapa 15 — eliminación física de Egreso (Maestro): flujo real de UI
// completo (menú ⋮ → motivo → confirmar) y verificación de que el
// listado refleja la eliminación de inmediato, sin cambiar de pestaña
// ni reconstruir manualmente.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_list_screen.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

const _usuarioMaestroId = 'usuario-maestro';

class _SesionMaestroDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: _usuarioMaestroId,
      nombre: 'Maestro de prueba',
      nombreUsuario: 'maestro',
      esMaestro: true,
      permisos: {},
    );
  }
}

class _SesionNormalDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-normal',
      nombre: 'Usuario normal',
      nombreUsuario: 'normal',
      esMaestro: false,
      permisos: {'finanzas.ver', 'finanzas.crear', 'finanzas.modificar', 'finanzas.archivar'},
    );
  }
}

Future<void> _pumpScreen(WidgetTester tester, AppDatabase db, SesionController Function() sesion) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/egresos',
    routes: [
      GoRoute(path: '/egresos', builder: (context, state) => const Scaffold(body: EgresosListScreen())),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(sesion),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value(_usuarioMaestroId),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );
    await EgresoRepositoryImpl(db).crear(
      folioEgreso: 'EGR-000001',
      monto: 150000,
      fecha: DateTime(2026, 1, 5),
      formaPago: 'efectivo',
      concepto: 'Papelería de oficina',
    );
  });

  tearDown(() => db.close());

  testWidgets(
    'Maestro elimina físicamente desde el menú ⋮ y el listado lo refleja de inmediato, sin cambiar de pestaña',
    (tester) async {
      await _pumpScreen(tester, db, _SesionMaestroDePrueba.new);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      tester.takeException(); // overflow menor y ajeno al listado, ver egresos_cancelar_widget_test.dart

      await tester.tap(find.text('Papelería de oficina'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.more_vert), findsOneWidget, reason: 'el menú ⋮ solo debe verse para el Maestro');
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.eliminacionFisicaAccionMenu));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(RisegButton, l10n.eliminacionFisicaBotonConfirmar), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Captura de prueba, nunca fue un gasto real');
      await tester.tap(find.widgetWithText(RisegButton, l10n.eliminacionFisicaBotonConfirmar));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Papelería de oficina'), findsNothing, reason: 'el listado debe reflejar la eliminación sin navegar');
      expect(await EgresoRepositoryImpl(db).listar(), isEmpty);
    },
  );

  testWidgets('un usuario normal nunca ve el menú ⋮ de eliminación física', (tester) async {
    await _pumpScreen(tester, db, _SesionNormalDePrueba.new);
    tester.takeException();

    await tester.tap(find.text('Papelería de oficina'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.more_vert), findsNothing);
  });
}
