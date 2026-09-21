import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/descuentos_personal/domain/usecases/generar_plan_cuotas.dart';

void main() {
  group('siguienteFechaPagoNomina', () {
    test('desde un día 1–19 → día 20 del mismo mes', () {
      expect(siguienteFechaPagoNomina(DateTime(2026, 8, 6)), DateTime(2026, 8, 20));
    });

    test('desde el propio día 20 → día 5 del mes siguiente (estrictamente posterior, nunca el mismo día)', () {
      expect(siguienteFechaPagoNomina(DateTime(2026, 8, 20)), DateTime(2026, 9, 5));
    });

    test('desde un día 21–31 → día 5 del mes siguiente', () {
      expect(siguienteFechaPagoNomina(DateTime(2026, 8, 25)), DateTime(2026, 9, 5));
    });

    test('cruce de año: desde el 25 de diciembre → 5 de enero del año siguiente', () {
      expect(siguienteFechaPagoNomina(DateTime(2026, 12, 25)), DateTime(2027, 1, 5));
    });
  });

  group('generarPlanCuotas', () {
    test('préstamo único: 1 cuota en la fecha exacta elegida, sin desplazar', () {
      final plan = generarPlanCuotas(importeOriginal: 300000, numeroCuotas: 1, fechaPrimera: DateTime(2026, 8, 20));

      expect(plan, hasLength(1));
      expect(plan.single.numeroCuota, 1);
      expect(plan.single.fechaProgramada, DateTime(2026, 8, 20));
      expect(plan.single.importe, 300000);
    });

    test('préstamo en 2 parcialidades: cuota 2 cae en la siguiente quincena real, nunca +15 días fijos', () {
      final plan = generarPlanCuotas(importeOriginal: 70000, numeroCuotas: 2, fechaPrimera: DateTime(2026, 8, 20));

      expect(plan[0].fechaProgramada, DateTime(2026, 8, 20));
      expect(plan[1].fechaProgramada, DateTime(2026, 9, 5));
      expect(plan[0].importe, 35000);
      expect(plan[1].importe, 35000);
    });

    test('6 parcialidades encadenan 6 quincenas reales consecutivas', () {
      final plan = generarPlanCuotas(importeOriginal: 300000, numeroCuotas: 6, fechaPrimera: DateTime(2026, 1, 20));

      expect(plan.map((c) => c.fechaProgramada), [
        DateTime(2026, 1, 20),
        DateTime(2026, 2, 5),
        DateTime(2026, 2, 20),
        DateTime(2026, 3, 5),
        DateTime(2026, 3, 20),
        DateTime(2026, 4, 5),
      ]);
    });

    test(r'$1,000/3 vía el plan completo sigue sumando exactamente $1,000', () {
      final plan = generarPlanCuotas(importeOriginal: 100000, numeroCuotas: 3, fechaPrimera: DateTime(2026, 8, 20));

      expect(plan.fold<int>(0, (s, c) => s + c.importe), 100000);
    });

    test('primera fecha arbitraria (no alineada a quincena, elegida libremente por el Maestro) se respeta tal cual', () {
      final plan = generarPlanCuotas(importeOriginal: 70000, numeroCuotas: 2, fechaPrimera: DateTime(2026, 8, 12));

      expect(plan[0].fechaProgramada, DateTime(2026, 8, 12));
      expect(plan[1].fechaProgramada, DateTime(2026, 8, 20));
    });
  });
}
