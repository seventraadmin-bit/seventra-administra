import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'test_harness.dart';

void main() {
  testWidgets('no colapsable renderiza título y children siempre visibles', (tester) async {
    await pumpRiseg(
      tester,
      const RisegFormSection(title: 'Datos fiscales', children: [Text('Campo A')]),
    );

    expect(find.text('Datos fiscales'), findsOneWidget);
    expect(find.text('Campo A'), findsOneWidget);
  });

  testWidgets('collapsible: false inicial oculta los children hasta expandir', (tester) async {
    await pumpRiseg(
      tester,
      const RisegFormSection(
        title: 'Datos fiscales',
        collapsible: true,
        initiallyExpanded: false,
        children: [Text('Campo oculto')],
      ),
    );

    expect(find.text('Campo oculto'), findsNothing);

    await tester.tap(find.text('Datos fiscales'));
    await tester.pumpAndSettle();

    expect(find.text('Campo oculto'), findsOneWidget);
  });
}
