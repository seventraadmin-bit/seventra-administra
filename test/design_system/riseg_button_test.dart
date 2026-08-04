import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'test_harness.dart';

void main() {
  testWidgets('primary usa ElevatedButton, secondary OutlinedButton, ghost TextButton', (tester) async {
    await pumpRiseg(tester, const RisegButton(label: 'Primario', onPressed: null));
    expect(find.byType(ElevatedButton), findsOneWidget);

    await pumpRiseg(
      tester,
      const RisegButton(label: 'Secundario', variant: RisegButtonVariant.secondary, onPressed: null),
    );
    expect(find.byType(OutlinedButton), findsOneWidget);

    await pumpRiseg(tester, const RisegButton(label: 'Ghost', variant: RisegButtonVariant.ghost, onPressed: null));
    expect(find.byType(TextButton), findsOneWidget);
  });

  testWidgets('danger también usa ElevatedButton (relleno sólido)', (tester) async {
    await pumpRiseg(tester, RisegButton(label: 'Eliminar', variant: RisegButtonVariant.danger, onPressed: () {}));
    expect(find.byType(ElevatedButton), findsOneWidget);
  });

  testWidgets('onPressed nulo deshabilita el botón', (tester) async {
    await pumpRiseg(tester, const RisegButton(label: 'Deshabilitado', onPressed: null));
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('loading ignora el tap y no llama onPressed', (tester) async {
    var tapped = false;
    await pumpRiseg(
      tester,
      RisegButton(label: 'Guardando', loading: true, onPressed: () => tapped = true),
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(tapped, isFalse);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('tap normal sí llama onPressed', (tester) async {
    var tapped = false;
    await pumpRiseg(tester, RisegButton(label: 'Guardar', onPressed: () => tapped = true));

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
