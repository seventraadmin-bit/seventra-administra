import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/organizacion/domain/usecases/calcular_importe_proporcional_usecase.dart';

void main() {
  group('redondearCentavos — mitad se aleja de cero (Etapa 4I.1)', () {
    test('1.5 redondea a 2', () => expect(redondearCentavos(1.5), 2));
    test('-1.5 redondea a -2', () => expect(redondearCentavos(-1.5), -2));
    test('1.4 redondea a 1', () => expect(redondearCentavos(1.4), 1));
    test('1.6 redondea a 2', () => expect(redondearCentavos(1.6), 2));
    test('0.5 redondea a 1', () => expect(redondearCentavos(0.5), 1));
    test('valor exacto no cambia', () => expect(redondearCentavos(100.0), 100));
  });

  group('calcularImporteProporcional — una sola operación antes de redondear', () {
    test('periodo completo de 30 días reproduce el precio unitario exacto', () {
      final resultado = calcularImporteProporcional(
        precioUnitarioCentavos: 1800000,
        diasAplicables: 30,
        cantidadElementos: 1,
      );
      expect(resultado, 1800000);
    });

    test('varios elementos multiplican antes de dividir', () {
      final resultado = calcularImporteProporcional(
        precioUnitarioCentavos: 1500000,
        diasAplicables: 30,
        cantidadElementos: 2,
      );
      expect(resultado, 3000000);
    });

    test('monto no divisible exactamente entre 30 redondea al centavo más cercano', () {
      // 1,000,000 * 17 * 1 / 30 = 566,666.666... -> 566,667.
      final resultado = calcularImporteProporcional(
        precioUnitarioCentavos: 1000000,
        diasAplicables: 17,
        cantidadElementos: 1,
      );
      expect(resultado, 566667);
    });

    test('caso de redondeo exacto a mitad de centavo se aleja de cero', () {
      // 15 * 1 * 1 / 30 = 0.5 -> 1 (nunca 0).
      final resultado = calcularImporteProporcional(precioUnitarioCentavos: 15, diasAplicables: 1, cantidadElementos: 1);
      expect(resultado, 1);
    });

    test('Sportium: periodo de 31 días cobra más que uno de 28 (base fija de 30, nunca días reales del mes)', () {
      final periodo31Dias = calcularImporteProporcional(
        precioUnitarioCentavos: 1800000,
        diasAplicables: 31,
        cantidadElementos: 1,
      );
      final periodo28Dias = calcularImporteProporcional(
        precioUnitarioCentavos: 1800000,
        diasAplicables: 28,
        cantidadElementos: 1,
      );
      expect(periodo31Dias, greaterThan(1800000));
      expect(periodo28Dias, lessThan(1800000));
    });
  });
}
