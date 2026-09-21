// Etapa 17 — `ResumenFinancieroController` (portada ejecutiva de
// Finanzas). Regla crítica del pedido: si un Pago de $23,000 genera su
// Ingreso automático de $23,000, el Resumen debe contabilizar $23,000
// de entrada, NUNCA $46,000 — el controlador nunca suma
// `Pago.montoTotal` por separado, solo `Ingreso.monto` vía
// `ObtenerResumenFinancieroUseCase`. También cubre: Flujo neto =
// Ingresos - Egresos, y que "Por cobrar"/"Vencido" son saldos AL DÍA
// DE HOY, independientes del periodo seleccionado.

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_state.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';

void main() {
  late AppDatabase db;
  late String clienteId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final clienteRepo = ClienteRepositoryImpl(db);
    final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'));
    clienteId = cliente.id;
  });

  tearDown(() => db.close());

  Future<ResumenFinancieroState> cargarResumen() async {
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    // Espera a que el `Future.microtask(_cargar)` del `build()` inicial
    // termine, mismo patrón que las pruebas de controladores de Agenda.
    await container.read(resumenFinancieroControllerProvider.notifier).reintentarCarga();
    return container.read(resumenFinancieroControllerProvider);
  }

  test('un Pago que genera su Ingreso automático se contabiliza UNA sola vez, nunca duplicado', () async {
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final registrarPago = RegistrarPagoUseCase(PagoRepositoryImpl(db), ClienteRepositoryImpl(db), generarCodigo);

    await registrarPago.ejecutar(
      clienteId: clienteId,
      montoTotal: 2300000,
      fechaPago: DateTime.now(),
      formaPago: 'transferencia',
    );

    final resumen = await cargarResumen();

    expect(resumen.ingresosPeriodo, 2300000, reason: 'nunca 4,600,000 — el Pago no se suma aparte de su Ingreso');
  });

  test('Flujo después de deuda = Ingresos del periodo - Egresos del periodo', () async {
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final registrarPago = RegistrarPagoUseCase(PagoRepositoryImpl(db), ClienteRepositoryImpl(db), generarCodigo);
    final registrarEgreso = RegistrarEgresoUseCase(EgresoRepositoryImpl(db), generarCodigo, DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)));

    await registrarPago.ejecutar(
      clienteId: clienteId,
      montoTotal: 100000,
      fechaPago: DateTime.now(),
      formaPago: 'transferencia',
    );
    await registrarEgreso.ejecutar(
      monto: 40000,
      fecha: DateTime.now(),
      formaPago: 'efectivo',
      concepto: 'Renta de oficina',
    );

    final resumen = await cargarResumen();

    expect(resumen.ingresosPeriodo, 100000);
    expect(resumen.egresosPeriodo, 40000);
    expect(resumen.flujoDespuesDeuda, 60000);
  });

  test('sin movimientos registrados, el Resumen carga en ceros (nunca un error ni datos inventados)', () async {
    final resumen = await cargarResumen();

    expect(resumen.errorCarga, isNull);
    expect(resumen.ingresosPeriodo, 0);
    expect(resumen.egresosPeriodo, 0);
    expect(resumen.flujoDespuesDeuda, 0);
    expect(resumen.resumenCuentasPorCobrar.saldoPendiente, 0);
  });
}
