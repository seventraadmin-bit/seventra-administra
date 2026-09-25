// Etapa 4D — la clave de recuperación tiene que sobrevivir a una
// persona copiándola a mano desde un papel, meses después.
//
// Por eso las pruebas de abajo no se limitan al caso feliz: comprueban
// exactamente las formas en que la gente teclea mal —minúsculas, con o
// sin guiones, la O por el cero, la ele por el uno— y exigen que todas
// esas variantes abran igual, mientras que un carácter realmente
// distinto se rechace antes de gastar nada.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/respaldo/domain/portable/clave_recuperacion.dart';

Uint8List _bytes(int semilla) => Uint8List.fromList(List<int>.generate(20, (i) => (semilla + i * 7) & 0xFF));

void main() {
  group('Formato', () {
    test('34 caracteres de dato+checksum, presentados en grupos con prefijo', () {
      final texto = ClaveRecuperacion.formatear(_bytes(3));

      expect(texto, startsWith('RISEG-'));
      final partes = texto.split('-');
      expect(partes.first, 'RISEG');
      expect(partes.length, 10, reason: 'prefijo + 8 grupos de dato + 1 de checksum');
      expect(partes.skip(1).take(8).every((g) => g.length == 4), isTrue);
      expect(partes.last.length, 2);
    });

    test('sólo usa el alfabeto de Crockford: nunca aparecen I, L, O ni U', () {
      for (var semilla = 0; semilla < 40; semilla++) {
        final crudo = ClaveRecuperacion.formatear(_bytes(semilla)).replaceAll('-', '').substring(5);
        expect(
          RegExp(r'^[0-9A-HJKMNP-TV-Z]+$').hasMatch(crudo),
          isTrue,
          reason: 'semilla $semilla produjo un carácter ambiguo: $crudo',
        );
      }
    });

    test('rechaza material que no mida 20 bytes', () {
      expect(() => ClaveRecuperacion.formatear(Uint8List(19)), throwsArgumentError);
      expect(() => ClaveRecuperacion.formatear(Uint8List(21)), throwsArgumentError);
    });
  });

  group('Ida y vuelta', () {
    test('formatear e interpretar devuelven exactamente los mismos bytes', () {
      for (var semilla = 0; semilla < 64; semilla++) {
        final original = _bytes(semilla);
        expect(ClaveRecuperacion.interpretar(ClaveRecuperacion.formatear(original)), equals(original));
      }
    });

    test('todo cero y todo 0xFF también', () {
      for (final bytes in [Uint8List(20), Uint8List.fromList(List.filled(20, 0xFF))]) {
        expect(ClaveRecuperacion.interpretar(ClaveRecuperacion.formatear(bytes)), equals(bytes));
      }
    });
  });

  group('Cómo teclea la gente', () {
    final original = _bytes(11);
    final canonico = ClaveRecuperacion.formatear(original);

    void aceptaIgual(String variante, String porque) {
      expect(ClaveRecuperacion.interpretar(variante), equals(original), reason: porque);
    }

    test('en minúsculas', () => aceptaIgual(canonico.toLowerCase(), 'nadie respeta las mayúsculas'));

    test('sin ningún guion', () => aceptaIgual(canonico.replaceAll('-', ''), 'copiado de un solo tirón'));

    test('con espacios en vez de guiones', () => aceptaIgual(canonico.replaceAll('-', ' '), 'tecleado desde el papel'));

    test('con saltos de línea y tabuladores', () {
      aceptaIgual(canonico.replaceAll('-', '\n  \t'), 'pegado desde un PDF o un correo');
    });

    test('sin el prefijo RISEG', () {
      aceptaIgual(canonico.substring('RISEG-'.length), 'el prefijo es presentación, no dato');
    });

    test('con O mayúscula donde iba un cero', () {
      final conO = canonico.replaceAll('0', 'O');
      if (conO != canonico) aceptaIgual(conO, 'la confusión clásica de Crockford');
    });

    test('con I o L donde iba un uno', () {
      final conI = canonico.replaceAll('1', 'I');
      if (conI != canonico) aceptaIgual(conI, 'I se lee como 1');
      final conL = canonico.replaceAll('1', 'l');
      if (conL != canonico) aceptaIgual(conL, 'la ele minúscula también');
    });
  });

  group('Rechazos', () {
    final original = _bytes(5);
    final canonico = ClaveRecuperacion.formatear(original);

    test('un carácter cambiado por otro del alfabeto: lo caza el checksum', () {
      var detectados = 0;
      var probados = 0;
      final crudo = canonico.replaceAll('-', '').substring(5);
      for (var i = 0; i < crudo.length; i++) {
        for (final reemplazo in ['2', '7', 'K', 'Z']) {
          if (crudo[i] == reemplazo) continue;
          probados++;
          final roto = crudo.replaceRange(i, i + 1, reemplazo);
          if (ClaveRecuperacion.interpretar(roto) == null) detectados++;
        }
      }
      // El checksum es de 10 bits: se afirma sólo lo que garantiza,
      // ~1/1024 de errores inadvertidos. No se promete detección
      // universal de erratas ni de transposiciones.
      expect(probados, greaterThan(100));
      expect(
        detectados / probados,
        greaterThan(0.99),
        reason: 'con 10 bits de checksum se espera ~99.9% de detección, no el 100%',
      );
    });

    test('longitud incorrecta', () {
      final crudo = canonico.replaceAll('-', '').substring(5);
      expect(ClaveRecuperacion.interpretar(crudo.substring(0, 33)), isNull);
      expect(ClaveRecuperacion.interpretar('${crudo}5'), isNull);
      expect(ClaveRecuperacion.interpretar(''), isNull);
    });

    test('caracteres fuera del alfabeto', () {
      final crudo = canonico.replaceAll('-', '').substring(5);
      // La U no pertenece a Crockford y no se mapea a nada.
      expect(ClaveRecuperacion.interpretar(crudo.replaceRange(0, 1, 'U')), isNull);
      expect(ClaveRecuperacion.interpretar('${crudo.substring(0, 33)}#'), isNull);
    });

    test('checksum alterado con el dato intacto', () {
      final crudo = canonico.replaceAll('-', '').substring(5);
      final otroChecksum = crudo[33] == 'Z' ? 'Y' : 'Z';
      expect(ClaveRecuperacion.interpretar(crudo.replaceRange(33, 34, otroChecksum)), isNull);
    });

    test('texto que no se parece en nada a una clave', () {
      expect(ClaveRecuperacion.interpretar('no soy una clave de recuperación'), isNull);
    });
  });
}
