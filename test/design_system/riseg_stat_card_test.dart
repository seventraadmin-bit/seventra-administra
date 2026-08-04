import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'test_harness.dart';

void main() {
  testWidgets('renderiza label, value y delta', (tester) async {
    await pumpRiseg(
      tester,
      const RisegStatCard(
        label: 'Clientes activos',
        value: '128',
        delta: '+2 esta semana',
        deltaTone: RisegStatusTone.success,
      ),
    );

    expect(find.text('Clientes activos'), findsOneWidget);
    expect(find.text('128'), findsOneWidget);
    expect(find.text('+2 esta semana'), findsOneWidget);
  });

  testWidgets('onTap la vuelve interactiva', (tester) async {
    var tapped = false;
    await pumpRiseg(
      tester,
      RisegStatCard(label: 'Contratos', value: '7', onTap: () => tapped = true),
    );

    await tester.tap(find.text('Contratos'));
    expect(tapped, isTrue);
  });
}
