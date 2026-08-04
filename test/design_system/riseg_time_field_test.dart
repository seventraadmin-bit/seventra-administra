import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'test_harness.dart';

void main() {
  testWidgets('renderiza label y hora formateada', (tester) async {
    await pumpRiseg(
      tester,
      RisegTimeField(label: 'Hora de inicio', value: const TimeOfDay(hour: 8, minute: 30), onChanged: (_) {}),
    );

    expect(find.text('Hora de inicio'), findsOneWidget);
    expect(find.textContaining('8:30'), findsOneWidget);
  });

  testWidgets('tocar el campo abre el selector y confirmar dispara onChanged', (tester) async {
    TimeOfDay? seleccionada;
    await pumpRiseg(
      tester,
      RisegTimeField(
        label: 'Hora de inicio',
        value: const TimeOfDay(hour: 9, minute: 0),
        onChanged: (value) => seleccionada = value,
      ),
    );

    await tester.tap(find.byType(TextFormField));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(seleccionada, const TimeOfDay(hour: 9, minute: 0));
  });

  testWidgets('enabled: false no abre el selector', (tester) async {
    await pumpRiseg(
      tester,
      RisegTimeField(label: 'Hora', value: const TimeOfDay(hour: 9, minute: 0), onChanged: (_) {}, enabled: false),
    );

    await tester.tap(find.byType(TextFormField));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
  });
}
