// Etapa 19C — "Posición de caja, flujo real y proyección de
// compromisos". Pruebas de widget de la gestión simple de Cuentas
// financieras (Parte B): registrar vía el diálogo real refleja el
// listado de inmediato, el expediente muestra saldo derivado +
// historial con navegación real al Ingreso/Egreso de origen, corregir/
// activar/desactivar funcionan de punta a punta, y ninguna pantalla
// desborda en anchos angostos (Parte M).

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
import 'package:riseg_one/features/finanzas/presentation/cuentas_financieras/cuenta_financiera_expediente_screen.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_financieras/cuentas_financieras_list_screen.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';

class _SesionMaestroDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-maestro',
      nombre: 'Maestro de prueba',
      nombreUsuario: 'maestro',
      esMaestro: true,
      permisos: {},
    );
  }
}

Future<void> pump(
  WidgetTester tester,
  AppDatabase db, {
  required Size tamano,
  required ThemeData tema,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/finanzas/cuentas-financieras',
    routes: [
      GoRoute(
        path: '/finanzas/cuentas-financieras',
        builder: (context, state) => const Scaffold(body: CuentasFinancierasListScreen()),
      ),
      GoRoute(
        path: '/finanzas/cuentas-financieras/:id',
        builder: (context, state) => CuentaFinancieraExpedienteScreen(cuentaId: state.pathParameters['id']!),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
      ],
      child: MaterialApp.router(
        theme: tema,
        themeMode: ThemeMode.light,
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
            id: const Value('usuario-maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'usuario-maestro',
            passwordHash: 'x',
          ),
        );
    // Etapa 3B: autorizar revalida contra la base, así que la
    // sesión de esta prueba tiene que corresponder a una cuenta real.
    await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'usuario-maestro', nombre: 'Maestro de prueba', nombreUsuario: 'maestro', esMaestro: true, permisos: {}, ));
  });

  tearDown(() => db.close());

  testWidgets('registrar una cuenta financiera vía el diálogo real la refleja de inmediato en el listado', (tester) async {
    await pump(tester, db, tamano: const Size(1440, 900), tema: AppTheme.light());
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.text(l10n.cuentasFinancierasListadoVacioTitulo), findsOneWidget);

    await tester.tap(find.byKey(const Key('cuentas_financieras_boton_registrar')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byWidgetPredicate((w) => w is RisegTextField && w.label == l10n.registrarCuentaFinancieraCampoNombre),
        matching: find.byType(TextFormField),
      ),
      'BBVA Operativa',
    );
    await tester.enterText(
      find.descendant(
        of: find.byWidgetPredicate((w) => w is RisegTextField && w.label == l10n.registrarCuentaFinancieraCampoSaldoInicial),
        matching: find.byType(TextFormField),
      ),
      '50000',
    );
    await tester.tap(find.widgetWithText(RisegButton, l10n.cuentasFinancierasBotonRegistrar).last);
    await tester.pumpAndSettle();

    expect(find.text('BBVA Operativa'), findsOneWidget);
    expect(find.textContaining(r'$50,000.00'), findsWidgets);
  });

  testWidgets('el expediente deriva el saldo de los movimientos reales y permite corregir/desactivar/reactivar', (tester) async {
    final cuenta = await db.into(db.cuentaFinanciera).insertReturning(
          CuentaFinancieraCompanion.insert(
            codigo: 'CTA-0001',
            nombre: 'Efectivo caja chica',
            tipo: 'efectivo',
            saldoInicial: 1000000,
            fechaSaldoInicial: DateTime(2026, 1, 1),
          ),
        );
    await db.into(db.ingreso).insert(
          IngresoCompanion.insert(
            folioIngreso: 'ING-0001',
            monto: 200000,
            fecha: DateTime(2026, 2, 1),
            formaPago: 'efectivo',
            concepto: 'Depósito de prueba',
            cuentaFinancieraId: Value(cuenta.id),
          ),
        );

    await pump(tester, db, tamano: const Size(1440, 900), tema: AppTheme.light());
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.text('Efectivo caja chica'));
    await tester.pumpAndSettle();

    expect(find.byType(CuentaFinancieraExpedienteScreen), findsOneWidget);
    expect(find.textContaining(r'$12,000.00'), findsWidgets, reason: r'saldo derivado: $10,000 + $2,000 = $12,000');
    expect(find.text('Depósito de prueba'), findsOneWidget, reason: 'el historial muestra el movimiento real vinculado');
    expect(find.text(l10n.cuentaFinancieraEstatusActiva), findsOneWidget);

    // Desactivar conserva historial/saldo (invariante 11).
    await tester.tap(find.byKey(const Key('cuenta_financiera_expediente_menu_acciones')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.cuentaFinancieraBotonDesactivar));
    await tester.pumpAndSettle();

    expect(find.text(l10n.cuentaFinancieraEstatusInactiva), findsOneWidget);
    expect(find.textContaining(r'$12,000.00'), findsWidgets, reason: 'desactivar nunca altera el saldo derivado');
    expect(find.text('Depósito de prueba'), findsOneWidget, reason: 'desactivar nunca borra el historial');

    // Reactivar.
    await tester.tap(find.byKey(const Key('cuenta_financiera_expediente_menu_acciones')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.cuentaFinancieraBotonActivar));
    await tester.pumpAndSettle();
    expect(find.text(l10n.cuentaFinancieraEstatusActiva), findsOneWidget);

    // Corregir nombre.
    await tester.tap(find.widgetWithText(RisegButton, l10n.editarDeudaBotonConfirmar));
    await tester.pumpAndSettle();
    final campoNombre = find.descendant(
      of: find.byWidgetPredicate((w) => w is RisegTextField && w.label == l10n.registrarCuentaFinancieraCampoNombre),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(campoNombre, 'Efectivo caja chica (matriz)');
    await tester.tap(find.widgetWithText(RisegButton, l10n.editarDeudaBotonConfirmar).last);
    await tester.pumpAndSettle();

    expect(find.text('Efectivo caja chica (matriz)'), findsWidgets, reason: 'aparece en el AppBar y en el encabezado de sección');
  });

  testWidgets('una cuenta financiera con movimientos vinculados no puede eliminarse físicamente', (tester) async {
    final cuenta = await db.into(db.cuentaFinanciera).insertReturning(
          CuentaFinancieraCompanion.insert(
            codigo: 'CTA-0001',
            nombre: 'BBVA Operativa',
            tipo: 'banco',
            saldoInicial: 0,
            fechaSaldoInicial: DateTime(2026, 1, 1),
          ),
        );
    await db.into(db.egreso).insert(
          EgresoCompanion.insert(
            folioEgreso: 'EGR-0001',
            monto: 50000,
            fecha: DateTime(2026, 2, 1),
            formaPago: 'transferencia',
            concepto: 'Pago de prueba',
            cuentaFinancieraId: Value(cuenta.id),
          ),
        );

    await pump(tester, db, tamano: const Size(1440, 900), tema: AppTheme.light());
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.text('BBVA Operativa'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cuenta_financiera_expediente_menu_acciones')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cuenta_financiera_expediente_boton_eliminar_fisicamente')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).last, 'motivo de prueba');
    await tester.tap(find.widgetWithText(RisegButton, l10n.eliminacionFisicaBotonConfirmar));
    await tester.pumpAndSettle();

    // Bloqueada silenciosamente (mismo criterio que Deuda) — la
    // pantalla sigue mostrando el expediente, la cuenta no desaparece.
    expect(find.byType(CuentaFinancieraExpedienteScreen), findsOneWidget);
    final cuentaTrasIntento = await (db.select(db.cuentaFinanciera)..where((t) => t.id.equals(cuenta.id))).getSingleOrNull();
    expect(cuentaTrasIntento, isNotNull, reason: 'una cuenta con Egreso vinculado nunca se elimina físicamente');
  });

  for (final tamano in [const Size(1366, 768), const Size(1024, 768), const Size(700, 900), const Size(500, 900)]) {
    for (final tema in [AppTheme.light(), AppTheme.dark()]) {
      testWidgets('el listado de Cuentas financieras no desborda a ${tamano.width.toInt()}px (${tema.brightness.name})', (tester) async {
        await db.into(db.cuentaFinanciera).insert(
              CuentaFinancieraCompanion.insert(
                codigo: 'CTA-0001',
                nombre: 'BBVA Operativa',
                tipo: 'banco',
                ultimosDigitos: const Value('4215'),
                saldoInicial: 5000000,
                fechaSaldoInicial: DateTime(2026, 1, 1),
              ),
            );
        await pump(tester, db, tamano: tamano, tema: tema);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
