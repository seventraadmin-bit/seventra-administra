import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'test_harness.dart';

void main() {
  testWidgets('modo normal renderiza un TextField con el hint dado', (tester) async {
    await pumpRiseg(tester, const RisegSearchField(hint: 'Buscar cliente'));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Buscar cliente'), findsOneWidget);
  });

  testWidgets('compact: true colapsa a un IconButton', (tester) async {
    await pumpRiseg(tester, const RisegSearchField(hint: 'Buscar cliente', compact: true));
    expect(find.byType(IconButton), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('onChanged se llama al escribir', (tester) async {
    String? typed;
    await pumpRiseg(tester, RisegSearchField(hint: 'Buscar', onChanged: (value) => typed = value));

    await tester.enterText(find.byType(TextField), 'Sportium');
    expect(typed, 'Sportium');
  });
}
