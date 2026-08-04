import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'test_harness.dart';

void main() {
  testWidgets('renderiza label y, opcionalmente, ícono', (tester) async {
    await pumpRiseg(tester, const RisegStatusBadge(label: 'Cliente activo', tone: RisegStatusTone.success));
    expect(find.text('Cliente activo'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);

    await pumpRiseg(
      tester,
      const RisegStatusBadge(label: 'Contrato vencido', tone: RisegStatusTone.error, icon: Icons.error_outline),
    );
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('cada tono usa un color de texto distinto', (tester) async {
    await pumpRiseg(tester, const RisegStatusBadge(label: 'A', tone: RisegStatusTone.success));
    final successColor = tester.widget<Text>(find.text('A')).style!.color;

    await pumpRiseg(tester, const RisegStatusBadge(label: 'B', tone: RisegStatusTone.error));
    final errorColor = tester.widget<Text>(find.text('B')).style!.color;

    expect(successColor, isNot(equals(errorColor)));
  });
}
