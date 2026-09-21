// Etapa 2 — pruebas del helper puro de auditoría de correcciones
// sensibles (`lib/core/auditoria/diff_evento.dart`). Sin base de
// datos: `DiffEvento` no conoce ninguna tabla, solo arma el JSON
// before/after — estas pruebas cubren esa lógica de forma aislada y
// determinista.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/auditoria/diff_evento.dart';

void main() {
  group('DiffEvento', () {
    test('corrección con un solo campo — solo ese campo aparece en el JSON', () {
      final diff = DiffEvento()..anotar('monto', 35000, 42000);

      expect(diff.hayCambios, isTrue);
      expect(jsonDecode(diff.estadoAnteriorJson!), {'monto': 35000});
      expect(jsonDecode(diff.estadoNuevoJson!), {'monto': 42000});
    });

    test('corrección con múltiples campos — todos aparecen, en el orden anotado', () {
      final diff = DiffEvento()
        ..anotar('monto', 35000, 42000)
        ..anotar('deudaId', 'konfio', 'clara')
        ..anotar('proveedor', 'Proveedor A', 'Proveedor B');

      expect(jsonDecode(diff.estadoAnteriorJson!), {'monto': 35000, 'deudaId': 'konfio', 'proveedor': 'Proveedor A'});
      expect(jsonDecode(diff.estadoNuevoJson!), {'monto': 42000, 'deudaId': 'clara', 'proveedor': 'Proveedor B'});
    });

    test('no incluye campos sin cambio real, aunque se anoten explícitamente', () {
      final diff = DiffEvento()
        ..anotar('monto', 35000, 42000) // cambia
        ..anotar('proveedor', 'Mismo Proveedor', 'Mismo Proveedor') // no cambia
        ..anotar('observaciones', null, null); // no cambia (ambos null)

      final antes = jsonDecode(diff.estadoAnteriorJson!) as Map;
      final despues = jsonDecode(diff.estadoNuevoJson!) as Map;
      expect(antes.containsKey('proveedor'), isFalse);
      expect(antes.containsKey('observaciones'), isFalse);
      expect(despues.containsKey('proveedor'), isFalse);
      expect(antes, {'monto': 35000});
      expect(despues, {'monto': 42000});
    });

    test('sin ningún cambio real, hayCambios es false y los JSON son null (nunca "{}")', () {
      final diff = DiffEvento()
        ..anotar('monto', 35000, 35000)
        ..anotar('proveedor', 'Igual', 'Igual');

      expect(diff.hayCambios, isFalse);
      expect(diff.estadoAnteriorJson, isNull);
      expect(diff.estadoNuevoJson, isNull);
    });

    test('montos en centavos (int) se preservan exactos, sin pasar por double', () {
      final diff = DiffEvento()..anotar('monto', 123456789, 987654321);

      final antes = jsonDecode(diff.estadoAnteriorJson!) as Map;
      final despues = jsonDecode(diff.estadoNuevoJson!) as Map;
      expect(antes['monto'], isA<int>());
      expect(antes['monto'], 123456789);
      expect(despues['monto'], isA<int>());
      expect(despues['monto'], 987654321);
    });

    test('DateTime se serializa siempre con toIso8601String(), de forma consistente', () {
      final antes = DateTime(2026, 1, 15, 10, 30);
      final despues = DateTime(2026, 3, 20, 16, 45);
      final diff = DiffEvento()..anotar('fecha', antes, despues);

      final antesJson = jsonDecode(diff.estadoAnteriorJson!) as Map;
      final despuesJson = jsonDecode(diff.estadoNuevoJson!) as Map;
      expect(antesJson['fecha'], antes.toIso8601String());
      expect(despuesJson['fecha'], despues.toIso8601String());
      // Nunca el formato inestable de toString().
      expect(antesJson['fecha'], isNot(antes.toString()));
    });

    test('dos DateTime distintos por milisegundos sí cuentan como cambio', () {
      final a = DateTime(2026, 1, 1, 0, 0, 0, 0);
      final b = DateTime(2026, 1, 1, 0, 0, 0, 1);
      final diff = DiffEvento()..anotar('fecha', a, b);

      expect(diff.hayCambios, isTrue);
    });
  });

  group('motivoEsValido', () {
    test('rechaza null', () => expect(motivoEsValido(null), isFalse));
    test('rechaza cadena vacía', () => expect(motivoEsValido(''), isFalse));
    test('rechaza solo espacios/tabs', () => expect(motivoEsValido('   \t  '), isFalse));
    test('acepta un motivo real, incluso con espacios alrededor', () => expect(motivoEsValido('  Corrección de monto  '), isTrue));
  });
}
