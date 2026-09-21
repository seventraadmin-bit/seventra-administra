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

  // BUG REAL (Etapa "Usuarios, permisos y UX de seguridad"): cambiar el
  // NÚMERO de pestañas hace que `didUpdateWidget` construya un
  // `TabController` nuevo, y el estado usaba
  // `SingleTickerProviderStateMixin` — que solo admite UN ticker en toda
  // la vida del `State`, aunque el anterior se haya dispuesto. Reventaba
  // con "multiple tickers were created".
  //
  // No era teórico: Configuración pasa de 4 pestañas a 2 en cuanto la
  // sesión deja de ser Maestra (Respaldo y Bóveda son Maestro-only), y
  // ahí se reprodujo.
  testWidgets('quitar pestañas en caliente no revienta (multiple tickers)', (tester) async {
    await pumpRiseg(tester, RisegTabs(tabs: tabs, selectedIndex: 0, onChanged: (_) {}));
    await tester.pumpAndSettle();

    const menos = [RisegTabItem(label: 'General')];
    await pumpRiseg(tester, RisegTabs(tabs: menos, selectedIndex: 0, onChanged: (_) {}));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Contactos'), findsNothing);
  });

  testWidgets('agregar pestañas en caliente tampoco revienta', (tester) async {
    await pumpRiseg(tester, const RisegTabs(tabs: [RisegTabItem(label: 'General')], selectedIndex: 0, onChanged: _nada));
    await tester.pumpAndSettle();

    await pumpRiseg(tester, RisegTabs(tabs: tabs, selectedIndex: 0, onChanged: (_) {}));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Contactos'), findsOneWidget);
  });

  testWidgets('un selectedIndex que ya no existe se acota en vez de romper el rango', (tester) async {
    // Caso exacto de Configuración: se está en Respaldo (índice 2) y la
    // sesión deja de ser Maestra, así que solo quedan 2 pestañas. El
    // llamador corregirá su propio estado, pero el `TabController` no
    // puede nacer fuera de rango mientras tanto.
    await pumpRiseg(tester, RisegTabs(tabs: tabs, selectedIndex: 2, onChanged: (_) {}));
    await tester.pumpAndSettle();

    const dos = [RisegTabItem(label: 'General'), RisegTabItem(label: 'Direcciones')];
    await pumpRiseg(tester, RisegTabs(tabs: dos, selectedIndex: 2, onChanged: (_) {}));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Direcciones'), findsOneWidget);
  });
}

void _nada(int _) {}
