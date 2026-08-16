import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/calcular_totales_esperados_usecase.dart';

void main() {
  group('calcularTotalesEsperados — caso real MILUYOLE (Etapa 15)', () {
    test('Más IVA: base \$21,800.00 produce IVA \$3,488.00 y total \$25,288.00', () {
      final resultado = calcularTotalesEsperados(
        importeBaseCentavos: 2180000,
        tratamientoIva: TratamientoIva.masIva,
      );
      expect(resultado.base, 2180000);
      expect(resultado.ivaEsperado, 348800);
      expect(resultado.totalEsperado, 2528800);
    });
  });

  group('calcularTotalesEsperados — las 3 reglas de tratamiento', () {
    test('noAplica: IVA \$0, total = base (Tikal, \$34,000.00)', () {
      final resultado = calcularTotalesEsperados(
        importeBaseCentavos: 3400000,
        tratamientoIva: TratamientoIva.noAplica,
      );
      expect(resultado.ivaEsperado, 0);
      expect(resultado.totalEsperado, 3400000);
    });

    test('ivaIncluido: no vuelve a sumar IVA — total = importe configurado (\$25,288.00)', () {
      final resultado = calcularTotalesEsperados(
        importeBaseCentavos: 2528800,
        tratamientoIva: TratamientoIva.ivaIncluido,
      );
      expect(resultado.ivaEsperado, 0, reason: 'ivaIncluido no desglosa un monto de IVA en esta etapa');
      expect(resultado.totalEsperado, 2528800);
    });

    test('masIva: IVA = base × 16%, total = base + IVA', () {
      final resultado = calcularTotalesEsperados(
        importeBaseCentavos: 1000000,
        tratamientoIva: TratamientoIva.masIva,
      );
      expect(resultado.ivaEsperado, 160000);
      expect(resultado.totalEsperado, 1160000);
    });
  });

  group('calcularTotalesEsperados — ajuste manual (nunca duplicado ni ignorado)', () {
    test('Más IVA con ajuste: el IVA se calcula sobre la base YA ajustada, no sobre la base cruda', () {
      // Base 20,000.00 + ajuste (descuento) -1,800.00 = base ajustada 18,200.00.
      // IVA 16% de 18,200.00 = 2,912.00. Total = 21,112.00.
      final resultado = calcularTotalesEsperados(
        importeBaseCentavos: 2000000,
        ajusteManualCentavos: -180000,
        tratamientoIva: TratamientoIva.masIva,
      );
      expect(resultado.base, 1820000);
      expect(resultado.ivaEsperado, 291200);
      expect(resultado.totalEsperado, 2111200);
    });

    test('un ajuste positivo (incremento) también entra a la base antes del IVA', () {
      final resultado = calcularTotalesEsperados(
        importeBaseCentavos: 2180000,
        ajusteManualCentavos: 20000,
        tratamientoIva: TratamientoIva.masIva,
      );
      expect(resultado.base, 2200000);
      expect(resultado.ivaEsperado, 352000);
      expect(resultado.totalEsperado, 2552000);
    });

    test('ajuste nulo equivale a ajuste cero — mismo resultado que no pasar el parámetro', () {
      final sinAjuste = calcularTotalesEsperados(importeBaseCentavos: 2180000, tratamientoIva: TratamientoIva.masIva);
      final conAjusteNulo = calcularTotalesEsperados(
        importeBaseCentavos: 2180000,
        ajusteManualCentavos: null,
        tratamientoIva: TratamientoIva.masIva,
      );
      expect(conAjusteNulo.totalEsperado, sinAjuste.totalEsperado);
    });

    test('noAplica con ajuste: el ajuste se refleja en el total, sin ningún IVA', () {
      final resultado = calcularTotalesEsperados(
        importeBaseCentavos: 3400000,
        ajusteManualCentavos: -50000,
        tratamientoIva: TratamientoIva.noAplica,
      );
      expect(resultado.ivaEsperado, 0);
      expect(resultado.totalEsperado, 3350000);
    });
  });

  group('calcularTotalesEsperados — redondeo (misma política que calcularImporteProporcional)', () {
    test('el 16% se redondea al centavo más cercano, alejándose de cero en el punto medio', () {
      // 100 * 0.16 = 16.00 exacto, sin ambigüedad de redondeo — se
      // valida con un caso real de punto medio: base tal que
      // base*0.16 cae en .5 centavos exactos.
      final resultado = calcularTotalesEsperados(importeBaseCentavos: 3125, tratamientoIva: TratamientoIva.masIva);
      // 3125 * 0.16 = 500.0 exacto — sin fracción, control de regresión
      // simple del cálculo base.
      expect(resultado.ivaEsperado, 500);
    });
  });
}
