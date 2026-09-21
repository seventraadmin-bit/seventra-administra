// Etapa 17 — resumen del conjunto filtrado de Pagos (Pagos recibidos |
// Monto recibido | Monto aplicado | Pendiente de aplicar). Solo cuenta
// Pagos `registrado` — uno `cancelado` no es dinero vigente.

import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_resumen.dart';

PagoData _pago({required String estatus, required int montoTotal, required int montoAplicado}) {
  final ahora = DateTime(2026, 1, 1);
  return PagoData(
    id: 'pago-$estatus-$montoTotal-$montoAplicado',
    createdAt: ahora,
    updatedAt: ahora,
    cicloVidaRegistro: 'activo',
    folioPago: 'PAG-000001',
    clienteId: 'cliente-1',
    montoTotal: montoTotal,
    montoAplicado: montoAplicado,
    fechaPago: ahora,
    formaPago: 'transferencia',
    estatus: estatus,
  );
}

void main() {
  test('suma monto total y aplicado solo de Pagos registrados', () {
    final resumen = calcularResumenPagos([
      _pago(estatus: 'registrado', montoTotal: 100000, montoAplicado: 100000),
      _pago(estatus: 'registrado', montoTotal: 50000, montoAplicado: 0),
      _pago(estatus: 'cancelado', montoTotal: 999999, montoAplicado: 999999),
    ]);

    expect(resumen.pagosRecibidos, 2);
    expect(resumen.montoRecibido, 150000);
    expect(resumen.montoAplicado, 100000);
  });

  test('pendiente de aplicar es montoRecibido - montoAplicado (un Pago sin aplicar todavía)', () {
    final resumen = calcularResumenPagos([
      _pago(estatus: 'registrado', montoTotal: 23000, montoAplicado: 0),
    ]);

    expect(resumen.pendienteAplicar, 23000);
  });

  test('un Pago totalmente aplicado no deja nada pendiente de aplicar', () {
    final resumen = calcularResumenPagos([
      _pago(estatus: 'registrado', montoTotal: 23000, montoAplicado: 23000),
    ]);

    expect(resumen.pendienteAplicar, 0);
  });

  test('lista vacía produce un resumen en ceros', () {
    final resumen = calcularResumenPagos([]);

    expect(resumen.pagosRecibidos, 0);
    expect(resumen.montoRecibido, 0);
    expect(resumen.montoAplicado, 0);
    expect(resumen.pendienteAplicar, 0);
  });
}
