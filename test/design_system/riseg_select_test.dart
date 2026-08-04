import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'test_harness.dart';

void main() {
  testWidgets('renderiza label, opciones y responde a onChanged', (tester) async {
    String? seleccionado;
    await pumpRiseg(
      tester,
      RisegSelect<String>(
        label: 'Tipo de Sucursal',
        value: null,
        items: const [
          RisegSelectItem(value: 'oficina', label: 'Oficina Administrativa'),
          RisegSelectItem(value: 'bodega', label: 'Bodega'),
        ],
        onChanged: (value) => seleccionado = value,
      ),
    );

    expect(find.text('Tipo de Sucursal'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bodega').last);
    await tester.pumpAndSettle();

    expect(seleccionado, 'bodega');
  });

  testWidgets('errorText se muestra', (tester) async {
    await pumpRiseg(
      tester,
      const RisegSelect<String>(
        label: 'Tipo',
        value: null,
        items: [RisegSelectItem(value: 'a', label: 'A')],
        onChanged: null,
        errorText: 'Selecciona una opción',
      ),
    );
    expect(find.text('Selecciona una opción'), findsOneWidget);
  });

  testWidgets('enabled: false deshabilita el control', (tester) async {
    await pumpRiseg(
      tester,
      RisegSelect<String>(
        label: 'Tipo',
        value: 'a',
        items: const [RisegSelectItem(value: 'a', label: 'A')],
        onChanged: (_) {},
        enabled: false,
      ),
    );
    final field = tester.widget<DropdownButtonFormField<String>>(find.byType(DropdownButtonFormField<String>));
    expect(field.onChanged, isNull);
  });
}
