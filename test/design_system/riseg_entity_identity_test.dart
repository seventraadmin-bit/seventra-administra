import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'test_harness.dart';

void main() {
  group('inicialesDe', () {
    test('dos palabras — primera letra de cada una', () {
      expect(inicialesDe('Sportium Cuautitlán'), 'SC');
    });

    test('una sola palabra — solo su primera letra', () {
      expect(inicialesDe('Sportium'), 'S');
    });

    test('espacios accidentales no producen iniciales vacías', () {
      expect(inicialesDe('  Ana   María  '), 'AM');
    });

    test('cadena vacía no lanza — devuelve vacío', () {
      expect(inicialesDe(''), '');
      expect(inicialesDe('   '), '');
    });
  });

  group('RisegEntityIdentity', () {
    testWidgets('sin imagenPath, cae al fallback de iniciales — nunca un error visual', (tester) async {
      await pumpRiseg(
        tester,
        const RisegEntityIdentity(primario: 'Sportium Cuautitlán', secundario: 'CLI-000001'),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Sportium Cuautitlán'), findsOneWidget);
      expect(find.text('CLI-000001'), findsOneWidget);
      expect(find.text('SC'), findsOneWidget, reason: 'fallback de iniciales cuando no hay imagen real');
    });

    testWidgets('con una ruta de imagen inexistente, también cae al fallback — nunca lanza', (tester) async {
      await pumpRiseg(
        tester,
        const RisegEntityIdentity(
          primario: 'Ana Gómez',
          secundario: 'No. 1',
          imagenPath: 'C:/ruta/que/no/existe.png',
          forma: RisegEntityImageShape.circular,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('AG'), findsOneWidget);
    });

    testWidgets('sin secundario, no renderiza una segunda línea', (tester) async {
      await pumpRiseg(tester, const RisegEntityIdentity(primario: 'Solo primario'));

      expect(tester.takeException(), isNull);
      expect(find.text('Solo primario'), findsOneWidget);
    });

    testWidgets('forma cuadradaRedondeada no lanza excepción', (tester) async {
      await pumpRiseg(
        tester,
        const RisegEntityIdentity(
          primario: 'Morgan Atlacomulco',
          secundario: 'Sportium',
          forma: RisegEntityImageShape.cuadradaRedondeada,
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
