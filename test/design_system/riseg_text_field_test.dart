import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'test_harness.dart';

void main() {
  testWidgets('renderiza label, hint y responde a onChanged', (tester) async {
    String? changed;
    await pumpRiseg(
      tester,
      RisegTextField(label: 'RFC', hint: 'AAAA000101AAA', onChanged: (value) => changed = value),
    );

    expect(find.text('RFC'), findsOneWidget);
    expect(find.text('AAAA000101AAA'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'SPO010101AA1');
    expect(changed, 'SPO010101AA1');
  });

  testWidgets('errorText se muestra', (tester) async {
    await pumpRiseg(tester, const RisegTextField(label: 'RFC', errorText: 'RFC inválido'));
    expect(find.text('RFC inválido'), findsOneWidget);
  });

  testWidgets('enabled: false deshabilita el campo', (tester) async {
    await pumpRiseg(tester, const RisegTextField(label: 'Campo', enabled: false));
    final field = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(field.enabled, isFalse);
  });

  testWidgets('autofocus reclama el foco al montarse', (tester) async {
    await pumpRiseg(tester, const RisegTextField(label: 'Campo', autofocus: true));
    await tester.pumpAndSettle();
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
  });
}
