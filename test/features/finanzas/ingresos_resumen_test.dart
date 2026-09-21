// Etapa 17 — resumen del conjunto filtrado de Ingresos (Ingresos
// totales | Automáticos | Manuales). "Automático"/"Manual" derivan
// EXCLUSIVAMENTE de `pagoId` (nullable, único) — el único discriminador
// real de origen; nunca inventado, nunca una columna aparte.

import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/presentation/ingresos/ingresos_resumen.dart';

IngresoData _ingreso({required String estatus, required int monto, String? pagoId}) {
  final ahora = DateTime(2026, 1, 1);
  return IngresoData(
    id: 'ingreso-$estatus-$monto-$pagoId',
    createdAt: ahora,
    updatedAt: ahora,
    cicloVidaRegistro: 'activo',
    pagoId: pagoId,
    folioIngreso: 'ING-000001',
    monto: monto,
    fecha: ahora,
    formaPago: 'transferencia',
    concepto: 'Concepto de prueba',
    estatus: estatus,
  );
}

void main() {
  test('separa automáticos (pagoId != null) de manuales (pagoId == null)', () {
    final resumen = calcularResumenIngresos([
      _ingreso(estatus: 'registrado', monto: 23000, pagoId: 'pago-1'),
      _ingreso(estatus: 'registrado', monto: 5000),
    ]);

    expect(resumen.automaticos, 23000);
    expect(resumen.manuales, 5000);
    expect(resumen.totalIngresos, 28000);
  });

  test('un Ingreso cancelado nunca se suma (evita doble conteo de dinero que ya no cuenta)', () {
    final resumen = calcularResumenIngresos([
      _ingreso(estatus: 'registrado', monto: 23000, pagoId: 'pago-1'),
      _ingreso(estatus: 'cancelado', monto: 999999, pagoId: 'pago-2'),
    ]);

    expect(resumen.totalIngresos, 23000);
  });

  test('lista vacía produce un resumen en ceros', () {
    final resumen = calcularResumenIngresos([]);

    expect(resumen.totalIngresos, 0);
    expect(resumen.automaticos, 0);
    expect(resumen.manuales, 0);
  });
}
