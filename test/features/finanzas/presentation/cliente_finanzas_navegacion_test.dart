// Etapa 17 — navegación encadenada Cliente → Finanzas (pedido §9):
// desde "Datos de cobranza" del expediente de Cliente, "Ver cuentas
// por cobrar"/"Ver pagos" abren Finanzas con el filtro de Cliente ya
// aplicado (`?clienteId=...`), leído una sola vez por la pantalla
// destino vía `GoRouterState`.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/cuentas_por_cobrar_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/cuentas_por_cobrar_list_screen.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/presentation/clientes/cliente_expediente_screen.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

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

Future<GoRouter> _pumpConRouter(WidgetTester tester, AppDatabase db, String clienteId) async {
  tester.view.physicalSize = const Size(1440, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/comercial/clientes/$clienteId',
    routes: [
      GoRoute(
        path: '/comercial/clientes/:id',
        builder: (context, state) => ClienteExpedienteScreen(clienteId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/finanzas/cuentas-por-cobrar',
        builder: (context, state) => const Scaffold(body: CuentasPorCobrarListScreen()),
      ),
      GoRoute(path: '/finanzas/pagos', builder: (context, state) => const Scaffold(body: PagosListScreen())),
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
  return router;
}

void main() {
  late AppDatabase db;
  late String clienteId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final clienteRepo = ClienteRepositoryImpl(db);
    final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'));
    clienteId = cliente.id;

    // Un segundo Cliente + Pago propio — si el filtro no se aplicara
    // de verdad, este Pago "contaminaría" la vista de Sportium.
    final otro = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000002', nombreComercial: 'Otro Cliente'));
    await RegistrarPagoUseCase(PagoRepositoryImpl(db), clienteRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)))
        .ejecutar(clienteId: otro.id, montoTotal: 999999, fechaPago: DateTime.now(), formaPago: 'efectivo');
  });

  tearDown(() => db.close());

  testWidgets('"Ver pagos" navega a Pagos con el filtro de Cliente ya aplicado', (tester) async {
    await _pumpConRouter(tester, db, clienteId);

    expect(find.text('Sportium'), findsWidgets);
    await tester.ensureVisible(find.byKey(const Key('cliente_boton_ver_pagos')));
    await tester.tap(find.byKey(const Key('cliente_boton_ver_pagos')));
    await tester.pumpAndSettle();

    expect(find.byType(PagosListScreen), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(PagosListScreen)));
    expect(container.read(pagosControllerProvider).clienteId, clienteId);
  });

  testWidgets('"Ver cuentas por cobrar" navega a Cuentas por cobrar con el filtro de Cliente ya aplicado', (tester) async {
    await _pumpConRouter(tester, db, clienteId);

    await tester.ensureVisible(find.byKey(const Key('cliente_boton_ver_cuentas_por_cobrar')));
    await tester.tap(find.byKey(const Key('cliente_boton_ver_cuentas_por_cobrar')));
    await tester.pumpAndSettle();

    expect(find.byType(CuentasPorCobrarListScreen), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(CuentasPorCobrarListScreen)));
    expect(container.read(cuentasPorCobrarControllerProvider).clienteId, clienteId);
  });
}
