import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'test_harness.dart';

void main() {
  testWidgets('renderiza título, descripción y acciones', (tester) async {
    await pumpRiseg(
      tester,
      RisegSectionHeader(
        title: 'Contratos',
        description: '4 registrados',
        primaryAction: RisegButton(label: 'Nuevo', onPressed: () {}),
      ),
    );

    expect(find.text('Contratos'), findsOneWidget);
    expect(find.text('4 registrados'), findsOneWidget);
    expect(find.text('Nuevo'), findsOneWidget);
  });

  testWidgets('sin acciones ni descripción, solo renderiza el título', (tester) async {
    await pumpRiseg(tester, const RisegSectionHeader(title: 'Solo título'));
    expect(find.text('Solo título'), findsOneWidget);
  });
}
