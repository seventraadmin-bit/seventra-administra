import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'test_harness.dart';

void main() {
  testWidgets('renderiza título, mensaje y acción', (tester) async {
    var tapped = false;
    await pumpRiseg(
      tester,
      RisegEmptyState(
        title: 'Sin servicios',
        message: 'Este cliente aún no tiene servicios.',
        primaryAction: RisegButton(label: 'Asignar', onPressed: () => tapped = true),
      ),
    );

    expect(find.text('Sin servicios'), findsOneWidget);
    expect(find.text('Este cliente aún no tiene servicios.'), findsOneWidget);

    await tester.tap(find.text('Asignar'));
    expect(tapped, isTrue);
  });
}
