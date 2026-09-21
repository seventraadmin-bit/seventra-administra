import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/descuentos_personal/domain/usecases/sugerir_primera_fecha_descuento.dart';

void main() {
  group('sugerirPrimeraFechaDescuento', () {
    test('caso del pedido: préstamo solicitado el 19/08/2026 → sugiere pago el 20/08/2026', () {
      final fecha = sugerirPrimeraFechaDescuento(DateTime(2026, 8, 19));

      expect(fecha, DateTime(2026, 8, 20));
    });

    test('día 6 (borde inferior del rango 6–20) → primera quincena del mismo mes (paga día 20)', () {
      final fecha = sugerirPrimeraFechaDescuento(DateTime(2026, 8, 6));

      expect(fecha, DateTime(2026, 8, 20));
    });

    test('día 20 (borde superior del rango 6–20) → primera quincena del mismo mes (paga día 20)', () {
      final fecha = sugerirPrimeraFechaDescuento(DateTime(2026, 8, 20));

      expect(fecha, DateTime(2026, 8, 20));
    });

    test('día 21 (borde inferior del rango 21–fin de mes) → segunda quincena, paga día 5 del mes siguiente', () {
      final fecha = sugerirPrimeraFechaDescuento(DateTime(2026, 8, 21));

      expect(fecha, DateTime(2026, 9, 5));
    });

    test('día 31 (fin de mes de 31 días) → segunda quincena, paga día 5 del mes siguiente', () {
      final fecha = sugerirPrimeraFechaDescuento(DateTime(2026, 8, 31));

      expect(fecha, DateTime(2026, 9, 5));
    });

    test('día 1 (borde inferior del rango 1–5) → segunda quincena del MES ANTERIOR, paga día 5 de este mes', () {
      final fecha = sugerirPrimeraFechaDescuento(DateTime(2026, 8, 1));

      expect(fecha, DateTime(2026, 8, 5));
    });

    test('día 5 (borde superior del rango 1–5) → segunda quincena del MES ANTERIOR, paga día 5 de este mes', () {
      final fecha = sugerirPrimeraFechaDescuento(DateTime(2026, 8, 5));

      expect(fecha, DateTime(2026, 8, 5));
    });

    test('cruce de año: día 3 de enero → segunda quincena de diciembre del año anterior, paga día 5 de enero', () {
      final fecha = sugerirPrimeraFechaDescuento(DateTime(2026, 1, 3));

      expect(fecha, DateTime(2026, 1, 5));
    });

    test('cruce de año: día 25 de diciembre → segunda quincena de diciembre, paga día 5 de enero siguiente', () {
      final fecha = sugerirPrimeraFechaDescuento(DateTime(2026, 12, 25));

      expect(fecha, DateTime(2027, 1, 5));
    });
  });
}
