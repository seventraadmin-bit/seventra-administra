// Etapa 19B — "Compra ↔ Tarjeta de crédito ↔ Deuda". Pruebas de
// widget: registrar una Compra con tarjeta vía la pantalla real
// refleja de inmediato el saldo en el expediente de la tarjeta (sin
// recargar manualmente, mismo patrón ya corregido en Deudas/Egresos),
// un movimiento de tipo Cargo permite navegar al expediente real de la
// Compra que lo originó, y ninguna de las dos pantallas desborda en
// los anchos estándar × claro/oscuro.

import 'package:drift/drift.dart' show Value;
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
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/compras/presentation/compra_expediente_screen.dart';
import 'package:riseg_one/features/compras/presentation/compras_list_screen.dart';
import 'package:riseg_one/features/compras/presentation/registrar_compra_screen.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/deudas_credito/deuda_expediente_screen.dart';
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

Finder botonConEtiqueta(String etiqueta) => find.widgetWithText(RisegButton, etiqueta);

Future<void> pump(
  WidgetTester tester,
  AppDatabase db, {
  required Size tamano,
  required ThemeData tema,
  String rutaInicial = '/finanzas/deudas-y-credito',
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: rutaInicial,
    routes: [
      GoRoute(
        path: '/finanzas/deudas-y-credito/:id',
        builder: (context, state) => DeudaExpedienteScreen(deudaId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/compras', builder: (context, state) => const Scaffold(body: ComprasListScreen())),
      GoRoute(path: '/compras/nueva', builder: (context, state) => const RegistrarCompraScreen()),
      GoRoute(path: '/compras/:id', builder: (context, state) => CompraExpedienteScreen(compraId: state.pathParameters['id']!)),
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
  });

  tearDown(() => db.close());

  Future<String> crearTarjeta(AppDatabase db) async {
    final egresoRepo = EgresoRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final registrar = RegistrarDeudaUseCase(deudaRepo, generarCodigo);
    final creada = (await registrar.ejecutar(
      nombre: 'TDC BBVA',
      tipo: 'tarjetaCredito',
      fechaOrigen: DateTime(2026, 1, 1),
      importeOriginal: 5000000,
      saldoInicial: 2000000,
      tarjetaUltimosDigitos: '4215',
      tarjetaLimiteCredito: 5000000,
    ) as RegistrarDeudaExitoso)
        .deuda;
    return creada.id;
  }

  testWidgets(
    'registrar una Compra con tarjeta vía la pantalla real refleja el saldo de inmediato en el expediente de la tarjeta '
    '(pop real, sin recarga manual)',
    (tester) async {
      final deudaId = await crearTarjeta(db);
      await pump(tester, db, tamano: const Size(1440, 900), tema: AppTheme.light(), rutaInicial: '/finanzas/deudas-y-credito/$deudaId');
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(find.textContaining(r'$20,000.00'), findsWidgets, reason: 'saldo inicial visible antes de comprar');

      // Navega a "Registrar compra" (misma ruta real que usa el botón
      // de Compras), simulando que el usuario abre esa pantalla desde
      // otra parte de la app durante la misma sesión. `push()` no debe
      // esperarse aquí: su Future solo resuelve cuando la ruta hace
      // `pop`, que ocurre más abajo al confirmar — esperarlo antes
      // bloquea la prueba indefinidamente (nada más bombea frames
      // mientras tanto).
      final BuildContext context = tester.element(find.byType(DeudaExpedienteScreen));
      final registradaFuture = GoRouter.of(context).push<bool>('/compras/nueva');

      await tester.pumpAndSettle();

      // Destino → Gasto directo PRIMERO (evita depender de un catálogo
      // de Artículos) — el campo Concepto solo existe una vez que el
      // destino ya no es Inventario.
      await tester.tap(find.byWidgetPredicate((w) => w is RisegSelect<String> && w.label == l10n.compraPartidaCampoDestino));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.compraPartidaOpcionGastoDirecto).last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(of: find.byWidgetPredicate((w) => w is RisegTextField && w.label == l10n.compraPartidaCampoConcepto), matching: find.byType(TextFormField)),
        'Uniformes de prueba',
      );
      await tester.enterText(
        find.descendant(of: find.byWidgetPredicate((w) => w is RisegTextField && w.label == l10n.compraPartidaCampoCantidad), matching: find.byType(TextFormField)),
        '1',
      );
      await tester.enterText(
        find.descendant(of: find.byWidgetPredicate((w) => w is RisegTextField && w.label == l10n.compraPartidaCampoCostoUnitario), matching: find.byType(TextFormField)),
        '5000',
      );

      // Forma de pago → Tarjeta.
      await tester.tap(find.byWidgetPredicate((w) => w is RisegSelect<String> && w.label == l10n.compraCampoFormaPago));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.formaPagoTarjeta).last);
      await tester.pumpAndSettle();

      // Selecciona la única tarjeta activa disponible.
      await tester.tap(find.byWidgetPredicate((w) => w is RisegSelect<String?> && w.label == l10n.compraCampoTarjeta));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('TDC BBVA').last);
      await tester.pumpAndSettle();

      final botonRegistrar = botonConEtiqueta(l10n.compraRegistrarDialogoTitulo).last;
      await tester.ensureVisible(botonRegistrar);
      await tester.pumpAndSettle();
      await tester.tap(botonRegistrar);
      await tester.pumpAndSettle();

      expect(find.text(l10n.compraGuardadaExito), findsOneWidget);

      // `RegistrarCompraScreen` ya hizo `context.pop(true)` al
      // confirmar (parte del `pumpAndSettle` de arriba) — de vuelta en
      // el expediente de la tarjeta sin llamar nada manualmente.
      final registrada = await registradaFuture;
      expect(registrada, isTrue);

      expect(find.textContaining(r'$25,000.00'), findsWidgets, reason: r'saldo debe reflejar $20,000 + $5,000 de inmediato');
    },
  );

  testWidgets('un movimiento de tipo Cargo en el historial de la tarjeta permite navegar al expediente real de la Compra', (tester) async {
    final egresoRepo = EgresoRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    final deudaId = await crearTarjeta(db);
    await db.into(db.compra).insert(
          CompraCompanion.insert(
            id: const Value('compra-seed'),
            folioCompra: 'COM-000099',
            fecha: DateTime.now(),
            formaPago: 'tarjeta',
            deudaId: Value(deudaId),
          ),
        );
    await deudaRepo.registrarCargoCompra(
      deudaId: deudaId,
      compraId: 'compra-seed',
      monto: 500000,
      fecha: DateTime.now(),
      observaciones: 'Compra COM-000099 · Ferretería de prueba',
    );

    await pump(tester, db, tamano: const Size(1440, 900), tema: AppTheme.light(), rutaInicial: '/finanzas/deudas-y-credito/$deudaId');
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.text(l10n.deudaBotonVerCompra), findsOneWidget);
    await tester.ensureVisible(find.text(l10n.deudaBotonVerCompra));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.deudaBotonVerCompra));
    await tester.pumpAndSettle();

    expect(find.text('COM-000099'), findsWidgets, reason: 'debe navegar al expediente real de la Compra que originó el cargo');
  });

  group('responsive/tema — expediente de tarjeta con historial de Compra', () {
    for (final tamano in const [Size(1366, 768), Size(1024, 768), Size(700, 900), Size(500, 900)]) {
      for (final tema in [(nombre: 'claro', data: AppTheme.light()), (nombre: 'oscuro', data: AppTheme.dark())]) {
        testWidgets('${tamano.width.toInt()}×${tamano.height.toInt()}, ${tema.nombre}: cero overflow', (tester) async {
          final egresoRepo = EgresoRepositoryImpl(db);
          final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
          final deudaId = await crearTarjeta(db);
          await db.into(db.compra).insert(
                CompraCompanion.insert(id: const Value('compra-seed'), folioCompra: 'COM-000099', fecha: DateTime.now(), formaPago: 'tarjeta'),
              );
          await deudaRepo.registrarCargoCompra(
            deudaId: deudaId,
            compraId: 'compra-seed',
            monto: 500000,
            fecha: DateTime.now(),
            observaciones: 'Compra COM-000099 · Ferretería de prueba',
          );

          await pump(tester, db, tamano: tamano, tema: tema.data, rutaInicial: '/finanzas/deudas-y-credito/$deudaId');

          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
