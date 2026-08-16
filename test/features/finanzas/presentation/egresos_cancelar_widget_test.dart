// Etapa 15 — reproducción real del bug reportado: pantalla roja al
// cancelar un Egreso desde su diálogo de detalle. Reproduce el flujo
// EXACTO de UI (abrir el detalle, tocar "Cancelar", confirmar en el
// diálogo anidado) — no solo llama al controller directamente.

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

Future<void> _pumpScreen(WidgetTester tester, AppDatabase db) async {
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
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
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
  late String egresoId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // `EgresoRepositoryImpl.cancelar` registra `actorUsuarioId` en
    // `EgresoEvento` (FK real hacia `Usuario`) — a diferencia de otros
    // controllers de este proyecto (`AgendaController`, que todavía no
    // lo propaga), `EgresosController.cancelar` sí lo hace, así que el
    // Usuario de la sesión de prueba debe existir físicamente o la
    // cancelación falla por violación de FK, nunca por el bug de UI que
    // esta prueba investiga.
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value(_usuarioMaestroId),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );
    final egreso = await EgresoRepositoryImpl(db).crear(
      folioEgreso: 'EGR-000001',
      monto: 150000,
      fecha: DateTime(2026, 1, 5),
      formaPago: 'efectivo',
      concepto: 'Papelería de oficina',
    );
    egresoId = egreso.id;
  });

  tearDown(() => db.close());

  testWidgets('cancelar un Egreso desde su diálogo de detalle no produce ninguna excepción', (tester) async {
    await _pumpScreen(tester, db);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    // La columna de estatus del listado tiene un overflow menor,
    // preexistente y ajeno a este hallazgo (`RisegStatusBadge` en una
    // columna de 130px) — se descarta aquí para no confundirlo con la
    // excepción real que esta prueba investiga.
    tester.takeException();

    await tester.tap(find.text('Papelería de oficina'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(RisegButton, l10n.egresoDetalleBotonCancelar),
      findsOneWidget,
      reason: 'el diálogo de detalle debe abrirse',
    );

    await tester.tap(find.widgetWithText(RisegButton, l10n.egresoDetalleBotonCancelar));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(RisegButton, l10n.cancelarEgresoConfirmacionConfirmar),
      findsWidgets,
      reason: 'diálogo de confirmación anidado',
    );

    await tester.enterText(find.byType(TextField).last, 'Registro duplicado por error');
    // El botón "Cancelar Egreso" del detalle sigue montado detrás del
    // diálogo de confirmación (mismo texto) — el último en el árbol es
    // el del diálogo anidado, el que realmente hay que tocar.
    await tester.tap(find.widgetWithText(RisegButton, l10n.cancelarEgresoConfirmacionConfirmar).last);
    await tester.pumpAndSettle();

    // Esta es la excepción real que reproducía el bug reportado —
    // "Failed assertion: '_dependents.isEmpty': is not true" — causada
    // por destruir `motivoController` de forma síncrona mientras el
    // diálogo de confirmación todavía estaba en su transición de
    // cierre (ver el fix en `egreso_detalle_dialog.dart`).
    expect(tester.takeException(), isNull, reason: 'no debe producirse ninguna excepción al cancelar');

    final actualizado = await EgresoRepositoryImpl(db).obtenerPorId(egresoId);
    expect(actualizado!.estatus, 'cancelado');
    expect(
      find.widgetWithText(RisegButton, l10n.egresoDetalleBotonCancelar),
      findsNothing,
      reason: 'un Egreso ya cancelado no debe ofrecer cancelarlo de nuevo',
    );
  });
}
