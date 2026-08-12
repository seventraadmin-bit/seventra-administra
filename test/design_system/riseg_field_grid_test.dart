// Pruebas de `RisegFieldGrid` (Etapa 15, hallazgo de layout de
// Organización) — verifica directamente, con anchos controlados, que
// el número de columnas responde a `AppBreakpoints` (3 columnas
// >= medium, 2 >= compact, 1 debajo), sin overflow en ningún caso.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

Future<void> _pumpConAncho(WidgetTester tester, double ancho, List<Widget> children) async {
  tester.view.physicalSize = Size(ancho, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: RisegFieldGrid(children: children)),
    ),
  );
}

List<Widget> _cuatroCampos() => [
      for (var i = 0; i < 4; i++) SizedBox(key: ValueKey('campo$i'), child: Text('Campo $i')),
    ];

void main() {
  testWidgets('ancho >= medium (1000): 3 columnas — los primeros 3 campos comparten la misma fila', (tester) async {
    await _pumpConAncho(tester, 1200, _cuatroCampos());

    final y0 = tester.getTopLeft(find.byKey(const ValueKey('campo0'))).dy;
    final y1 = tester.getTopLeft(find.byKey(const ValueKey('campo1'))).dy;
    final y2 = tester.getTopLeft(find.byKey(const ValueKey('campo2'))).dy;
    final y3 = tester.getTopLeft(find.byKey(const ValueKey('campo3'))).dy;

    expect(y0, y1);
    expect(y0, y2);
    expect(y3, greaterThan(y0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ancho >= compact y < medium (800): 2 columnas — solo los primeros 2 campos comparten fila', (
    tester,
  ) async {
    await _pumpConAncho(tester, 800, _cuatroCampos());

    final y0 = tester.getTopLeft(find.byKey(const ValueKey('campo0'))).dy;
    final y1 = tester.getTopLeft(find.byKey(const ValueKey('campo1'))).dy;
    final y2 = tester.getTopLeft(find.byKey(const ValueKey('campo2'))).dy;

    expect(y0, y1);
    expect(y2, greaterThan(y0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ancho < compact (400): 1 columna — cada campo en su propia fila', (tester) async {
    await _pumpConAncho(tester, 400, _cuatroCampos());

    final y0 = tester.getTopLeft(find.byKey(const ValueKey('campo0'))).dy;
    final y1 = tester.getTopLeft(find.byKey(const ValueKey('campo1'))).dy;
    final y2 = tester.getTopLeft(find.byKey(const ValueKey('campo2'))).dy;
    final y3 = tester.getTopLeft(find.byKey(const ValueKey('campo3'))).dy;

    expect(y1, greaterThan(y0));
    expect(y2, greaterThan(y1));
    expect(y3, greaterThan(y2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('campos con alturas distintas no se recortan (Wrap, no GridView)', (tester) async {
    await _pumpConAncho(tester, 1200, [
      const SizedBox(key: ValueKey('bajo'), height: 20, child: Text('Bajo')),
      const SizedBox(
        key: ValueKey('alto'),
        height: 80,
        child: Text('Alto\ncon\nvarias\nlíneas', maxLines: 4),
      ),
      const SizedBox(key: ValueKey('bajo2'), height: 20, child: Text('Bajo 2')),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('alto')), findsOneWidget);
  });
}
