import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'test_harness.dart';

void main() {
  const tabs = [
    RisegTabItem(label: 'General'),
    RisegTabItem(label: 'Direcciones'),
    RisegTabItem(label: 'Contactos'),
  ];

  testWidgets('renderiza todas las etiquetas', (tester) async {
    await pumpRiseg(tester, RisegTabs(tabs: tabs, selectedIndex: 0, onChanged: (_) {}));
    for (final tab in tabs) {
      expect(find.text(tab.label), findsOneWidget);
    }
  });

  testWidgets('tap en una pestaña dispara onChanged con el índice correcto', (tester) async {
    int? selected;
    await pumpRiseg(tester, RisegTabs(tabs: tabs, selectedIndex: 0, onChanged: (index) => selected = index));

    await tester.tap(find.text('Contactos'));
    await tester.pumpAndSettle();

    expect(selected, 2);
  });

  testWidgets('selectedIndex externo sincroniza el TabController', (tester) async {
    await pumpRiseg(tester, RisegTabs(tabs: tabs, selectedIndex: 1, onChanged: (_) {}));
    await tester.pumpAndSettle();

    await pumpRiseg(tester, RisegTabs(tabs: tabs, selectedIndex: 2, onChanged: (_) {}));
    await tester.pumpAndSettle();
    // No debe lanzar y debe seguir mostrando las tres pestañas.
    expect(find.text('Contactos'), findsOneWidget);
  });
}
