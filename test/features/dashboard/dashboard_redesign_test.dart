// Etapa 15 (rediseño visual del Dashboard) — pruebas específicas de la
// nueva presentación: Actividad reciente unificada y ordenada por
// fecha real (nunca una hora inventada), ausencia de tendencias
// ficticias (no existe fuente real de comparación contra el periodo
// anterior hoy), y responsive sin overflow con datos reales cargados
// (no solo con la base de datos vacía, que ya cubre
// `dashboard_screen_test.dart`).

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:riseg_one/app/app.dart';
import 'package:riseg_one/app/router/app_router.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

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

Future<AppDatabase> _sembrarActividadDePrueba() async {
  final db = AppDatabase(NativeDatabase.memory());
  final hoy = DateTime.now();

  final cliente = await db.into(db.cliente).insertReturning(
        ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'MIRABILIA'),
      );

  // Compra — la más antigua de las tres (hace 2 días).
  await db.into(db.compra).insert(
        CompraCompanion.insert(
          folioCompra: 'COM-000001',
          fecha: hoy.subtract(const Duration(days: 2)),
          proveedor: const Value('Ferretería ML'),
          formaPago: 'transferencia',
        ),
      );

  // Pago — la más reciente (hoy).
  await db.into(db.pago).insert(
        PagoCompanion.insert(
          folioPago: 'PAG-000001',
          clienteId: Value(cliente.id),
          montoTotal: 1750000,
          fechaPago: hoy,
          formaPago: 'transferencia',
        ),
      );

  // Movimiento de inventario — hace 1 día (queda en medio).
  final categoria = await db.into(db.categoriaArticulo).insertReturning(
        CategoriaArticuloCompanion.insert(nombre: 'Uniformes'),
      );
  final articulo = await db.into(db.articulo).insertReturning(
        ArticuloCompanion.insert(folio: 'ART-000001', nombre: 'CAMISOLA', categoriaId: categoria.id),
      );
  await db.into(db.movimientoInventario).insert(
        MovimientoInventarioCompanion.insert(
          articuloId: articulo.id,
          tipoMovimiento: 'entrada',
          cantidad: 5,
          fecha: hoy.subtract(const Duration(days: 1)),
        ),
      );

  return db;
}

Future<void> _pumpApp(WidgetTester tester, AppDatabase db, {Size tamano = const Size(1440, 900), bool oscuro = false}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(oscuro ? {'riseg_one.theme_mode': 'dark'} : {});

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        contarUsuariosProvider.overrideWith((ref) async => 1),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
        // Etapa 20: el Dashboard ahora también lee
        // `documentoPorEmitirRepositoryProvider` (alerta de documentos
        // por emitir) — depende de `attachmentStorageProvider`/
        // `path_provider` (no disponible bajo `flutter test`).
        attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
      ],
      child: RisegOneApp(router: createAppRouter()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Actividad reciente unificada ordena Pago (hoy) → Movimiento (ayer) → Compra (hace 2 días)', (tester) async {
    final db = await _sembrarActividadDePrueba();
    addTearDown(db.close);
    await _pumpApp(tester, db);

    expect(tester.takeException(), isNull);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.text(l10n.dashboardSeccionActividad), findsOneWidget);
    expect(find.text(l10n.dashboardActividadItemPago), findsOneWidget);
    expect(find.text(l10n.dashboardActividadItemCompra), findsOneWidget);
    // "entrada" → mismo texto que ya usa `movimientoTipoLabel` en el
    // resto del proyecto (Etapa 7A/7D), no un texto nuevo inventado.
    expect(find.text(l10n.movimientoTipoEntrada), findsOneWidget);

    // Orden real por fecha: el título de Pago (hoy) debe aparecer ANTES
    // que el de Compra (hace 2 días) en el árbol de widgets.
    final posicionPago = tester.getTopLeft(find.text(l10n.dashboardActividadItemPago)).dy;
    final posicionCompra = tester.getTopLeft(find.text(l10n.dashboardActividadItemCompra)).dy;
    expect(posicionPago, lessThan(posicionCompra), reason: 'Pago (hoy) debe listarse antes que Compra (hace 2 días)');
  });

  testWidgets('Sin ninguna actividad real, muestra el mensaje de vacío — nunca una tarjeta por tipo', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _pumpApp(tester, db);

    expect(tester.takeException(), isNull);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    expect(find.text(l10n.dashboardActividadVacia), findsOneWidget);
  });

  testWidgets('Ninguna tendencia/comparación ficticia contra periodo anterior — no existe fuente real hoy', (tester) async {
    final db = await _sembrarActividadDePrueba();
    addTearDown(db.close);
    await _pumpApp(tester, db);

    expect(tester.takeException(), isNull);

    // Etapa 15 (rediseño gerencial): un porcentaje YA es una métrica
    // real y esperada (Cobertura operativa, Margen operativo) — lo que
    // nunca debe aparecer es una flecha de tendencia/variación contra
    // un periodo anterior inexistente (ej. "↑ 8.4% vs. periodo
    // anterior"), no el símbolo "%" en sí.
    final textosConFlechaTendencia = find
        .byWidgetPredicate(
          (widget) => widget is Text && ((widget.data?.contains('↑') ?? false) || (widget.data?.contains('↓') ?? false)),
        )
        .evaluate();
    expect(textosConFlechaTendencia, isEmpty, reason: 'no debe mostrarse ninguna tendencia inventada (ej. "↑ 8.4% vs. periodo anterior")');
  });

  testWidgets('Ventana angosta (700px) con datos reales cargados, sin overflow', (tester) async {
    final db = await _sembrarActividadDePrueba();
    addTearDown(db.close);
    await _pumpApp(tester, db, tamano: const Size(700, 900));

    expect(tester.takeException(), isNull);
  });

  testWidgets('Ventana muy amplia (1920px) con datos reales cargados, sin overflow', (tester) async {
    final db = await _sembrarActividadDePrueba();
    addTearDown(db.close);
    await _pumpApp(tester, db, tamano: const Size(1920, 1080));

    expect(tester.takeException(), isNull);
  });

  testWidgets('Ventana 1366x768 (resolución común de laptop) con datos reales cargados, sin overflow', (tester) async {
    final db = await _sembrarActividadDePrueba();
    addTearDown(db.close);
    await _pumpApp(tester, db, tamano: const Size(1366, 768));

    expect(tester.takeException(), isNull);
  });

  testWidgets('Ventana ~1000px (breakpoint AppBreakpoints.medium) con datos reales cargados, sin overflow', (tester) async {
    final db = await _sembrarActividadDePrueba();
    addTearDown(db.close);
    await _pumpApp(tester, db, tamano: const Size(1000, 900));

    expect(tester.takeException(), isNull);
  });

  testWidgets('Modo oscuro con datos reales cargados, sin overflow', (tester) async {
    final db = await _sembrarActividadDePrueba();
    addTearDown(db.close);
    await _pumpApp(tester, db, oscuro: true);

    expect(tester.takeException(), isNull);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    expect(find.text(l10n.dashboardSeccionActividad), findsOneWidget);
  });

  testWidgets('Ventana 1536x864 con datos reales cargados, sin overflow', (tester) async {
    final db = await _sembrarActividadDePrueba();
    addTearDown(db.close);
    await _pumpApp(tester, db, tamano: const Size(1536, 864));

    expect(tester.takeException(), isNull);
  });

  testWidgets('Ventana 1024x768 con datos reales cargados, sin overflow', (tester) async {
    final db = await _sembrarActividadDePrueba();
    addTearDown(db.close);
    await _pumpApp(tester, db, tamano: const Size(1024, 768));

    expect(tester.takeException(), isNull);
  });

  testWidgets('Ventana 500x900 (ancho mínimo razonable) con datos reales cargados, sin overflow ni columnas forzadas', (tester) async {
    final db = await _sembrarActividadDePrueba();
    addTearDown(db.close);
    await _pumpApp(tester, db, tamano: const Size(500, 900));

    expect(tester.takeException(), isNull);
  });

  testWidgets('Ventana 1536x864 en modo oscuro, sin overflow', (tester) async {
    final db = await _sembrarActividadDePrueba();
    addTearDown(db.close);
    await _pumpApp(tester, db, tamano: const Size(1536, 864), oscuro: true);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Ventana 500x900 en modo oscuro, sin overflow', (tester) async {
    final db = await _sembrarActividadDePrueba();
    addTearDown(db.close);
    await _pumpApp(tester, db, tamano: const Size(500, 900), oscuro: true);

    expect(tester.takeException(), isNull);
  });

  group('Etapa 20 — Actividad reciente: agrupación (Parte 7)', () {
    testWidgets(
      '5 pagos del mismo Cliente el mismo día se agrupan en una sola fila con el conteo y la suma reales',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final hoy = DateTime.now();
        final cliente = await db.into(db.cliente).insertReturning(
              ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'SPORTIUM'),
            );
        for (var i = 1; i <= 5; i++) {
          await db.into(db.pago).insert(
                PagoCompanion.insert(
                  folioPago: 'PAG-00000$i',
                  clienteId: Value(cliente.id),
                  montoTotal: 100000 * i,
                  fechaPago: DateTime(hoy.year, hoy.month, hoy.day, i),
                  formaPago: 'transferencia',
                ),
              );
        }
        await _pumpApp(tester, db);
        expect(tester.takeException(), isNull);
        final l10n = await AppLocalizations.delegate.load(const Locale('es'));

        // 5 pagos → 1 sola fila agrupada, nunca 5 filas casi idénticas.
        expect(find.text(l10n.dashboardActividadPagosAgrupados(5)), findsOneWidget);
        expect(find.text(l10n.dashboardActividadItemPago), findsNothing, reason: 'ningún pago individual debe quedar suelto');
        expect(find.textContaining('SPORTIUM'), findsWidgets);
        // Suma real: 100000+200000+300000+400000+500000 = 1,500,000 centavos = $15,000.00
        expect(find.textContaining(r'$15,000.00'), findsWidgets, reason: 'el valor agrupado debe ser la SUMA real, nunca solo el primero');
      },
    );

    testWidgets(
      '2 pagos de Clientes distintos el mismo día NO se agrupan entre sí (eventos distintos)',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final hoy = DateTime.now();
        final clienteA = await db.into(db.cliente).insertReturning(
              ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'SPORTIUM'),
            );
        final clienteB = await db.into(db.cliente).insertReturning(
              ClienteCompanion.insert(codigo: 'CLI-000002', nombreComercial: 'MILOYILE'),
            );
        await db.into(db.pago).insert(
              PagoCompanion.insert(
                folioPago: 'PAG-000001',
                clienteId: Value(clienteA.id),
                montoTotal: 100000,
                fechaPago: hoy,
                formaPago: 'transferencia',
              ),
            );
        await db.into(db.pago).insert(
              PagoCompanion.insert(
                folioPago: 'PAG-000002',
                clienteId: Value(clienteB.id),
                montoTotal: 200000,
                fechaPago: hoy,
                formaPago: 'transferencia',
              ),
            );
        await _pumpApp(tester, db);
        expect(tester.takeException(), isNull);
        final l10n = await AppLocalizations.delegate.load(const Locale('es'));

        // Ninguno se agrupa (cada Cliente aparece 1 sola vez) — deben
        // mostrarse como 2 renglones individuales, nunca fusionados.
        expect(find.text(l10n.dashboardActividadItemPago), findsNWidgets(2));
        expect(find.textContaining('SPORTIUM'), findsWidgets);
        expect(find.textContaining('MILOYILE'), findsWidgets);
      },
    );

    testWidgets(
      '4 movimientos de salidaAsignacion el mismo día se agrupan; un movimiento de tipo distinto el mismo día NO se mezcla con ellos',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final hoy = DateTime.now();
        final categoria = await db.into(db.categoriaArticulo).insertReturning(
              CategoriaArticuloCompanion.insert(nombre: 'Uniformes'),
            );
        for (var i = 1; i <= 4; i++) {
          final articulo = await db.into(db.articulo).insertReturning(
                ArticuloCompanion.insert(folio: 'ART-00000$i', nombre: 'Artículo $i', categoriaId: categoria.id),
              );
          await db.into(db.movimientoInventario).insert(
                MovimientoInventarioCompanion.insert(
                  articuloId: articulo.id,
                  tipoMovimiento: 'salidaAsignacion',
                  cantidad: 1,
                  fecha: DateTime(hoy.year, hoy.month, hoy.day, i),
                ),
              );
        }
        final articuloEntrada = await db.into(db.articulo).insertReturning(
              ArticuloCompanion.insert(folio: 'ART-000009', nombre: 'Otro artículo', categoriaId: categoria.id),
            );
        await db.into(db.movimientoInventario).insert(
              MovimientoInventarioCompanion.insert(
                articuloId: articuloEntrada.id,
                tipoMovimiento: 'entrada',
                cantidad: 10,
                fecha: hoy,
              ),
            );

        await _pumpApp(tester, db);
        expect(tester.takeException(), isNull);
        final l10n = await AppLocalizations.delegate.load(const Locale('es'));

        expect(find.text(l10n.dashboardActividadArticulosAsignados(4)), findsOneWidget);
        // El movimiento de tipo "entrada" nunca se cuenta como parte del
        // grupo de asignaciones — sigue su propia etiqueta individual.
        expect(find.text(l10n.movimientoTipoEntrada), findsOneWidget);
      },
    );
  });

  group('Etapa 20 — Navegación por ID real', () {
    testWidgets(
      'Requiere atención → tarjeta con utilización alta navega (push) al expediente de ESA Deuda por ID, nunca por coincidencia de nombre',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final egresoRepo = EgresoRepositoryImpl(db);
        final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
        final registrar = RegistrarDeudaUseCase(deudaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));

        // Dos tarjetas con nombres parecidos — solo UNA tiene
        // utilización alta; si la navegación adivinara por nombre en
        // vez de usar el id real, podría aterrizar en la incorrecta.
        await registrar.ejecutar(
          nombre: 'TDC Santander',
          tipo: 'tarjetaCredito',
          fechaOrigen: DateTime(2026, 1, 1),
          importeOriginal: 5000000,
          saldoInicial: 500000,
          tarjetaLimiteCredito: 5000000,
        );
        final tarjetaAlta = (await registrar.ejecutar(
          nombre: 'TDC Santander Business',
          tipo: 'tarjetaCredito',
          fechaOrigen: DateTime(2026, 1, 1),
          importeOriginal: 5000000,
          saldoInicial: 4500000,
          tarjetaLimiteCredito: 5000000,
        ) as RegistrarDeudaExitoso)
            .deuda;

        await _pumpApp(tester, db);
        expect(tester.takeException(), isNull);
        final l10n = await AppLocalizations.delegate.load(const Locale('es'));

        await tester.tap(find.text(l10n.dashboardAlertaTarjetaUtilizacionAlta('TDC Santander Business')));
        await tester.pumpAndSettle();

        // Aterriza en el expediente REAL de esa Deuda — el folio único
        // de esa fila (nunca de la otra) confirma que navegó por ID.
        expect(find.textContaining(tarjetaAlta.folio), findsOneWidget);
        expect(find.byType(BackButton), findsOneWidget, reason: 'push (no go) deja el Dashboard en la pila, con botón de regreso real');
      },
    );
  });

  group('Etapa 20 — Saldo disponible de caja (5º KPI)', () {
    testWidgets('con cuentas financieras activas configuradas, muestra el saldo real derivado', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.into(db.cuentaFinanciera).insert(
            CuentaFinancieraCompanion.insert(
              codigo: 'CTA-0001',
              nombre: 'BBVA Operativa',
              tipo: 'banco',
              saldoInicial: 1000000,
              fechaSaldoInicial: DateTime(2026, 1, 1),
            ),
          );

      await _pumpApp(tester, db);
      expect(tester.takeException(), isNull);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(find.text(l10n.dashboardKpiSaldoCaja), findsOneWidget);
      expect(find.textContaining(r'$10,000.00'), findsWidgets, reason: 'saldo real derivado de la cuenta activa, nunca inventado');
    });

    testWidgets('sin ninguna cuenta financiera activa, muestra el estado honesto — nunca \$0.00 disfrazado de saldo real', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await _pumpApp(tester, db);
      expect(tester.takeException(), isNull);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(find.text(l10n.dashboardKpiSaldoCaja), findsOneWidget);
      expect(find.text(l10n.dashboardKpiSaldoCajaNoConfigurada), findsOneWidget);
    });
  });

  group('Etapa "Dashboard: posición financiera" — Crédito disponible (6º KPI) y "pago vencido"', () {
    testWidgets('con TDC activas, suma el disponible de todas — nunca mezclado con la caja', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final egresoRepo = EgresoRepositoryImpl(db);
      final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
      final registrar = RegistrarDeudaUseCase(deudaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));

      await registrar.ejecutar(
        nombre: 'Konfío Empresarial',
        tipo: 'tarjetaCredito',
        saldoInicial: 3000000,
        fechaSaldoInicial: DateTime(2026, 1, 1),
        tarjetaLimiteCredito: 4000000, // disponible $10,000
      );
      await registrar.ejecutar(
        nombre: 'Clara Empresarial',
        tipo: 'tarjetaCredito',
        saldoInicial: 500000,
        fechaSaldoInicial: DateTime(2026, 1, 1),
        tarjetaLimiteCredito: 2000000, // disponible $15,000
      );

      await _pumpApp(tester, db);
      expect(tester.takeException(), isNull);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(find.text(l10n.dashboardKpiCreditoDisponible), findsOneWidget);
      expect(find.textContaining(r'$25,000.00'), findsWidgets, reason: 'suma de ambas tarjetas, nunca un total combinado con la caja');
    });

    testWidgets('sin ninguna TDC activa, muestra el estado honesto — nunca \$0.00 disfrazado de disponible real', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await _pumpApp(tester, db);
      expect(tester.takeException(), isNull);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(find.text(l10n.dashboardKpiCreditoDisponible), findsOneWidget);
      expect(find.text(l10n.dashboardKpiCreditoDisponibleSinTarjetas), findsOneWidget);
    });

    testWidgets('una TDC con un ciclo cubierto viejo (ciclos reales saltados) aparece en "Requiere atención" como pago vencido', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final egresoRepo = EgresoRepositoryImpl(db);
      final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
      final registrar = RegistrarDeudaUseCase(deudaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));

      await registrar.ejecutar(
        nombre: 'TDC Konfío vencida',
        tipo: 'tarjetaCredito',
        saldoInicial: 300000,
        fechaSaldoInicial: DateTime(2026, 1, 1),
        tarjetaLimiteCredito: 4000000,
        tarjetaReglaFechaPago: 'diaFijo',
        tarjetaDiaPago: 10,
        // Conciliado hace mucho — con el día 10 fijo, el ciclo real de
        // este mes ya pasó de largo sin registrarse: "vencida".
        tarjetaVencimientoCubiertoHasta: DateTime(2025, 1, 10),
      );

      await _pumpApp(tester, db);
      expect(tester.takeException(), isNull);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(find.text(l10n.dashboardAlertaTarjetaPagoVencido('TDC Konfío vencida')), findsOneWidget);
    });
  });
}
