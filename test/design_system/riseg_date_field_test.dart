import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'test_harness.dart';

void main() {
  testWidgets('renderiza label y fecha formateada', (tester) async {
    await pumpRiseg(
      tester,
      RisegDateField(label: 'Fecha de inicio', value: DateTime(2026, 8, 5), onChanged: (_) {}),
    );

    expect(find.text('Fecha de inicio'), findsOneWidget);
    expect(find.textContaining('2026'), findsOneWidget);
  });

  testWidgets('sin valor muestra el campo vacío', (tester) async {
    await pumpRiseg(
      tester,
      RisegDateField(label: 'Fecha de inicio', value: null, onChanged: (_) {}),
    );

    final campo = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(campo.initialValue, isEmpty);
  });

  testWidgets('tocar el campo abre el selector y confirmar dispara onChanged', (tester) async {
    DateTime? seleccionada;
    await pumpRiseg(
      tester,
      RisegDateField(
        label: 'Fecha de inicio',
        value: DateTime(2026, 8, 5),
        onChanged: (value) => seleccionada = value,
      ),
    );

    await tester.tap(find.byType(TextFormField));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(seleccionada, DateTime(2026, 8, 5));
  });

  testWidgets('enabled: false no abre el selector', (tester) async {
    await pumpRiseg(
      tester,
      RisegDateField(label: 'Fecha', value: DateTime(2026, 8, 5), onChanged: (_) {}, enabled: false),
    );

    await tester.tap(find.byType(TextFormField));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('muestra helperText y errorText', (tester) async {
    await pumpRiseg(
      tester,
      RisegDateField(
        label: 'Fecha',
        value: null,
        onChanged: (_) {},
        helperText: 'Selecciona una fecha',
        errorText: 'Campo obligatorio',
      ),
    );

    expect(find.text('Selecciona una fecha'), findsNothing, reason: 'errorText reemplaza a helperText en Material');
    expect(find.text('Campo obligatorio'), findsOneWidget);
  });
}
