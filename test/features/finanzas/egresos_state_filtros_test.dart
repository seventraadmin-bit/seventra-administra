// Etapa 17 — filtro de Origen/Forma de pago de Egresos, aplicado EN
// MEMORIA sobre la página ya cargada (mismo criterio que Ingresos).
// Origen deriva de `ClasificarEgresosPorOrigenUseCase`
// (`origenPorEgreso`, resuelto una sola vez en el controlador).

import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_state.dart';
import 'package:riseg_one/features/reportes/domain/usecases/clasificar_egresos_por_origen_usecase.dart' show OrigenEgreso;

EgresoData _egreso({required int monto, String formaPago = 'efectivo'}) {
  final ahora = DateTime(2026, 1, 1);
  return EgresoData(
    id: 'egreso-$monto-$formaPago',
    createdAt: ahora,
    updatedAt: ahora,
    cicloVidaRegistro: 'activo',
    folioEgreso: 'EGR-000001',
    monto: monto,
    fecha: ahora,
    formaPago: formaPago,
    concepto: 'Concepto de prueba',
    estatus: 'registrado',
  );
}

void main() {
  final nomina = _egreso(monto: 1000);
  final compra = _egreso(monto: 2000, formaPago: 'transferencia');
  final manual = _egreso(monto: 3000);

  final origenPorEgreso = {nomina.id: OrigenEgreso.nomina, compra.id: OrigenEgreso.compra};
  final egresos = [nomina, compra, manual];

  test('sin filtros, todos los Egresos son visibles', () {
    final state = const EgresosState().copyWith(egresos: egresos, origenPorEgreso: origenPorEgreso);
    expect(state.egresosFiltrados, hasLength(3));
  });

  test('filtro Origen Nómina deja solo los clasificados como nomina', () {
    final state = const EgresosState()
        .copyWith(egresos: egresos, origenPorEgreso: origenPorEgreso, origen: FiltroOrigenEgreso.nomina);
    expect(state.egresosFiltrados, hasLength(1));
    expect(state.egresosFiltrados.first.id, nomina.id);
  });

  test('filtro Origen Manual incluye los sin clasificación conocida (fallback seguro)', () {
    final state = const EgresosState()
        .copyWith(egresos: egresos, origenPorEgreso: origenPorEgreso, origen: FiltroOrigenEgreso.manual);
    expect(state.egresosFiltrados, hasLength(1));
    expect(state.egresosFiltrados.first.id, manual.id);
  });

  test('filtro Forma de pago combina con Origen', () {
    final state = const EgresosState().copyWith(
      egresos: egresos,
      origenPorEgreso: origenPorEgreso,
      origen: FiltroOrigenEgreso.compra,
      formaPago: 'transferencia',
    );
    expect(state.egresosFiltrados, hasLength(1));
    expect(state.egresosFiltrados.first.id, compra.id);
  });

  test('totalPeriodo es la suma de los tres orígenes, nunca una segunda suma independiente', () {
    final state = const EgresosState().copyWith(totalNomina: 1000, totalCompra: 2000, totalManual: 3000);
    expect(state.totalPeriodo, 6000);
  });
}
