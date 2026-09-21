// Etapa 17 — filtros de Origen/Forma de pago de Ingresos, aplicados EN
// MEMORIA sobre la página ya cargada (el repositorio no los soporta
// como parámetro) — nunca una consulta nueva por filtro.

import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/presentation/ingresos/ingresos_state.dart';

IngresoData _ingreso({required int monto, String? pagoId, String formaPago = 'transferencia'}) {
  final ahora = DateTime(2026, 1, 1);
  return IngresoData(
    id: 'ingreso-$monto-$pagoId-$formaPago',
    createdAt: ahora,
    updatedAt: ahora,
    cicloVidaRegistro: 'activo',
    pagoId: pagoId,
    folioIngreso: 'ING-000001',
    monto: monto,
    fecha: ahora,
    formaPago: formaPago,
    concepto: 'Concepto de prueba',
    estatus: 'registrado',
  );
}

void main() {
  final ingresos = [
    _ingreso(monto: 1000, pagoId: 'pago-1', formaPago: 'transferencia'),
    _ingreso(monto: 2000, formaPago: 'efectivo'),
    _ingreso(monto: 3000, formaPago: 'transferencia'),
  ];

  test('sin filtros, todos los Ingresos son visibles', () {
    const state = IngresosState();
    expect(state.copyWith(ingresos: ingresos).ingresosFiltrados.length, 3);
  });

  test('filtro Origen automático deja solo los que tienen pagoId', () {
    final state = const IngresosState().copyWith(ingresos: ingresos, origen: FiltroOrigenIngreso.automatico);
    expect(state.ingresosFiltrados, hasLength(1));
    expect(state.ingresosFiltrados.first.monto, 1000);
  });

  test('filtro Origen manual deja solo los que NO tienen pagoId', () {
    final state = const IngresosState().copyWith(ingresos: ingresos, origen: FiltroOrigenIngreso.manual);
    expect(state.ingresosFiltrados, hasLength(2));
    expect(state.ingresosFiltrados.map((i) => i.monto), containsAll([2000, 3000]));
  });

  test('filtro Forma de pago combina con Origen', () {
    final state = const IngresosState()
        .copyWith(ingresos: ingresos, origen: FiltroOrigenIngreso.manual, formaPago: 'efectivo');
    expect(state.ingresosFiltrados, hasLength(1));
    expect(state.ingresosFiltrados.first.monto, 2000);
  });

  test('hayFiltrosActivos refleja cualquier filtro (repositorio o local) activo', () {
    const vacio = IngresosState();
    expect(vacio.hayFiltrosActivos, isFalse);
    expect(vacio.copyWith(origen: FiltroOrigenIngreso.manual).hayFiltrosActivos, isTrue);
    expect(vacio.copyWith(formaPago: 'efectivo').hayFiltrosActivos, isTrue);
    expect(vacio.copyWith(servicioId: 'servicio-1').hayFiltrosActivos, isTrue);
  });
}
