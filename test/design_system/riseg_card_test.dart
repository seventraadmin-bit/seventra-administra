import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'test_harness.dart';

void main() {
  testWidgets('standard y subtle renderizan su contenido sin ser interactivas', (tester) async {
    await pumpRiseg(tester, const RisegCard(child: Text('contenido')));
    expect(find.text('contenido'), findsOneWidget);
    expect(find.byType(InkWell), findsNothing);

    await pumpRiseg(tester, const RisegCard(variant: RisegCardVariant.subtle, child: Text('contenido')));
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('interactive responde a tap', (tester) async {
    var tapped = false;
    await pumpRiseg(
      tester,
      RisegCard(variant: RisegCardVariant.interactive, onTap: () => tapped = true, child: const Text('card')),
    );

    await tester.tap(find.byType(InkWell));
    expect(tapped, isTrue);
  });

  testWidgets('interactive se activa con Enter al enfocarse', (tester) async {
    var tapped = false;
    await pumpRiseg(
      tester,
      RisegCard(variant: RisegCardVariant.interactive, onTap: () => tapped = true, child: const Text('card')),
    );

    final focusNode = tester.widget<InkWell>(find.byType(InkWell)).focusNode!;
    focusNode.requestFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(tapped, isTrue);
  });
}
