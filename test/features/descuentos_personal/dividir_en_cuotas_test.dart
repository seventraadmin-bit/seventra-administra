import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/descuentos_personal/domain/usecases/dividir_en_cuotas.dart';

void main() {
  group('dividirEnCuotas', () {
    test('pago único: 1 cuota igual al importe original', () {
      final cuotas = dividirEnCuotas(importeOriginal: 300000, numeroCuotas: 1);

      expect(cuotas, hasLength(1));
      expect(cuotas.single.numeroCuota, 1);
      expect(cuotas.single.importe, 300000);
    });

    test(r'$1,000/3 suma EXACTAMENTE el original — nunca $333.33 × 3 = $999.99', () {
      final cuotas = dividirEnCuotas(importeOriginal: 100000, numeroCuotas: 3);

      expect(cuotas.map((c) => c.importe), [33333, 33333, 33334]);
      expect(cuotas.fold<int>(0, (s, c) => s + c.importe), 100000);
    });

    test(r'botas $700 → 2 × $350 exactos', () {
      final cuotas = dividirEnCuotas(importeOriginal: 70000, numeroCuotas: 2);

      expect(cuotas.map((c) => c.importe), [35000, 35000]);
    });

    test(r'$3,000 en 6 parcialidades → 6 × $500 exactos', () {
      final cuotas = dividirEnCuotas(importeOriginal: 300000, numeroCuotas: 6);

      expect(cuotas.map((c) => c.importe), [50000, 50000, 50000, 50000, 50000, 50000]);
    });

    test('plan modificado: mismo importe con distinto número de cuotas sigue sumando exacto', () {
      final cuotas = dividirEnCuotas(importeOriginal: 70000, numeroCuotas: 3);

      expect(cuotas.fold<int>(0, (s, c) => s + c.importe), 70000);
      expect(cuotas.map((c) => c.numeroCuota), [1, 2, 3]);
    });

    test('el residuo se reparte en las ÚLTIMAS cuotas, nunca en la primera', () {
      final cuotas = dividirEnCuotas(importeOriginal: 1001, numeroCuotas: 3);

      // 1001 / 3 = 333 base, residuo 2 → las últimas 2 cuotas absorben +1.
      expect(cuotas.map((c) => c.importe), [333, 334, 334]);
    });

    test('numeroCuotas <= 0 lanza ArgumentError', () {
      expect(() => dividirEnCuotas(importeOriginal: 1000, numeroCuotas: 0), throwsArgumentError);
      expect(() => dividirEnCuotas(importeOriginal: 1000, numeroCuotas: -1), throwsArgumentError);
    });

    test('importeOriginal <= 0 lanza ArgumentError', () {
      expect(() => dividirEnCuotas(importeOriginal: 0, numeroCuotas: 2), throwsArgumentError);
      expect(() => dividirEnCuotas(importeOriginal: -100, numeroCuotas: 2), throwsArgumentError);
    });
  });
}
