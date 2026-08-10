import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/calcular_periodo_nomina.dart';

void main() {
  group('calcularPeriodoNomina', () {
    test('primera quincena: días 1 a 15, paga el día 20, siempre 15 días reales', () {
      final periodo = calcularPeriodoNomina(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera);

      expect(periodo.fechaInicio, DateTime(2026, 1, 1));
      expect(periodo.fechaFin, DateTime(2026, 1, 15));
      expect(periodo.fechaPago, DateTime(2026, 1, 20));
      expect(periodo.diasRealesPeriodo, 15);
    });

    test('segunda quincena en febrero no bisiesto (28 días): 16 al 28, 13 días reales', () {
      final periodo = calcularPeriodoNomina(anio: 2026, mes: 2, tipo: TipoPeriodoNomina.segunda);

      expect(periodo.fechaInicio, DateTime(2026, 2, 16));
      expect(periodo.fechaFin, DateTime(2026, 2, 28));
      expect(periodo.fechaPago, DateTime(2026, 3, 5));
      expect(periodo.diasRealesPeriodo, 13);
    });

    test('segunda quincena en febrero bisiesto (29 días): 16 al 29, 14 días reales', () {
      final periodo = calcularPeriodoNomina(anio: 2028, mes: 2, tipo: TipoPeriodoNomina.segunda);

      expect(periodo.fechaFin, DateTime(2028, 2, 29));
      expect(periodo.diasRealesPeriodo, 14);
    });

    test('segunda quincena en un mes de 30 días: 16 al 30, 15 días reales', () {
      final periodo = calcularPeriodoNomina(anio: 2026, mes: 4, tipo: TipoPeriodoNomina.segunda);

      expect(periodo.fechaFin, DateTime(2026, 4, 30));
      expect(periodo.diasRealesPeriodo, 15);
    });

    test('segunda quincena en un mes de 31 días: 16 al 31, 16 días reales', () {
      final periodo = calcularPeriodoNomina(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.segunda);

      expect(periodo.fechaFin, DateTime(2026, 1, 31));
      expect(periodo.diasRealesPeriodo, 16);
    });

    test('segunda quincena de diciembre paga el 5 de enero del año siguiente', () {
      final periodo = calcularPeriodoNomina(anio: 2026, mes: 12, tipo: TipoPeriodoNomina.segunda);

      expect(periodo.fechaFin, DateTime(2026, 12, 31));
      expect(periodo.fechaPago, DateTime(2027, 1, 5));
    });
  });
}
