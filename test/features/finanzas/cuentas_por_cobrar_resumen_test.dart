// Etapa 17 — resumen del conjunto filtrado de Cuentas por cobrar
// (Saldo pendiente | Saldo vencido | Por vencer | Pagadas). "Vencida"
// nunca se persiste (Resolución D de Marlon) — se deriva de
// fechaVencimiento vs. `hoy`, siempre inyectado desde afuera.

import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/cuentas_por_cobrar_resumen.dart';

CuentaPorCobrarData _cuenta({
  required String estatus,
  required int saldoOriginal,
  required int saldoPendiente,
  DateTime? fechaVencimiento,
}) {
  final ahora = DateTime(2026, 1, 1);
  return CuentaPorCobrarData(
    id: 'cxc-$estatus-$saldoPendiente-${fechaVencimiento?.millisecondsSinceEpoch}',
    createdAt: ahora,
    updatedAt: ahora,
    cicloVidaRegistro: 'activo',
    documentoPorEmitirId: 'doc-$estatus-$saldoPendiente',
    clienteId: 'cliente-1',
    tipoDocumento: 'cfdi',
    metodo: 'pue',
    requiereComplemento: false,
    fechaEmisionReal: ahora,
    importeEmitido: saldoOriginal,
    saldoOriginal: saldoOriginal,
    saldoPendiente: saldoPendiente,
    moneda: 'MXN',
    estatus: estatus,
    fechaVencimiento: fechaVencimiento,
  );
}

void main() {
  final hoy = DateTime(2026, 8, 20);

  test('suma saldoPendiente de todas las cuentas, pagada o no', () {
    final resumen = calcularResumenCuentasPorCobrar([
      _cuenta(estatus: 'pendiente', saldoOriginal: 100000, saldoPendiente: 100000),
      _cuenta(estatus: 'parcial', saldoOriginal: 50000, saldoPendiente: 20000),
      _cuenta(estatus: 'pagada', saldoOriginal: 30000, saldoPendiente: 0),
    ], hoy);

    expect(resumen.saldoPendiente, 120000);
  });

  test('saldo vencido solo cuenta cuentas con fechaVencimiento pasada y no pagadas', () {
    final resumen = calcularResumenCuentasPorCobrar([
      _cuenta(estatus: 'pendiente', saldoOriginal: 100000, saldoPendiente: 100000, fechaVencimiento: hoy.subtract(const Duration(days: 5))),
      _cuenta(estatus: 'pendiente', saldoOriginal: 50000, saldoPendiente: 50000, fechaVencimiento: hoy.add(const Duration(days: 5))),
      _cuenta(estatus: 'pendiente', saldoOriginal: 20000, saldoPendiente: 20000),
    ], hoy);

    expect(resumen.saldoVencido, 100000);
    expect(resumen.saldoPorVencer, 70000, reason: 'saldoPendiente(170000) - saldoVencido(100000)');
  });

  test('una cuenta pagada nunca cuenta como vencida aunque su fecha ya pasó (Resolución de Marlon)', () {
    final resumen = calcularResumenCuentasPorCobrar([
      _cuenta(estatus: 'pagada', saldoOriginal: 100000, saldoPendiente: 0, fechaVencimiento: hoy.subtract(const Duration(days: 30))),
    ], hoy);

    expect(resumen.saldoVencido, 0);
  });

  test('pagadas cuenta el número de cuentas con estatus pagada', () {
    final resumen = calcularResumenCuentasPorCobrar([
      _cuenta(estatus: 'pagada', saldoOriginal: 100000, saldoPendiente: 0),
      _cuenta(estatus: 'pagada', saldoOriginal: 50000, saldoPendiente: 0),
      _cuenta(estatus: 'parcial', saldoOriginal: 50000, saldoPendiente: 10000),
    ], hoy);

    expect(resumen.pagadas, 2);
  });

  test('lista vacía produce un resumen en ceros', () {
    final resumen = calcularResumenCuentasPorCobrar([], hoy);

    expect(resumen.saldoPendiente, 0);
    expect(resumen.saldoVencido, 0);
    expect(resumen.saldoPorVencer, 0);
    expect(resumen.pagadas, 0);
  });
}
