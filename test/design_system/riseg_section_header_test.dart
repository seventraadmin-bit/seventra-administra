import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'test_harness.dart';

/// Regresión de un `RenderFlex overflowed` real, encontrado primero en
/// `ArticuloExpedienteScreen` (Etapa 9D) con una sesión Maestro: el
/// encabezado del Artículo mostraba "Editar" (primaryAction) +
/// "Archivar"/"Eliminar físicamente (Maestro)" (secondaryAction, ya un
/// `Wrap` de 2 botones) — 3 botones junto al título, en un `Row` con
/// `Expanded` que solo podía encoger el título, nunca los botones. La
/// auditoría de los 41 usos reales de `RisegSectionHeader` (ver memoria
/// del proyecto) confirmó que el problema es estructural del
/// componente compartido, no de una pantalla — corregido aquí con
/// `Wrap`/`WrapAlignment.spaceBetween`. Estas pruebas cubren el
/// componente en aislamiento (sin depender de ninguna pantalla real)
/// con la forma exacta del peor caso encontrado.
void main() {
  testWidgets('renderiza título, descripción y acciones', (tester) async {
    await pumpRiseg(
      tester,
      RisegSectionHeader(
        title: 'Contratos',
        description: '4 registrados',
        primaryAction: RisegButton(label: 'Nuevo', onPressed: () {}),
      ),
    );

    expect(find.text('Contratos'), findsOneWidget);
    expect(find.text('4 registrados'), findsOneWidget);
    expect(find.text('Nuevo'), findsOneWidget);
  });

  testWidgets('sin acciones ni descripción, solo renderiza el título', (tester) async {
    await pumpRiseg(tester, const RisegSectionHeader(title: 'Solo título'));
    expect(find.text('Solo título'), findsOneWidget);
  });

  /// El encabezado real de `ArticuloExpedienteScreen` para una sesión
  /// Maestro sobre un Artículo activo — mismos textos, misma forma
  /// exacta de `primaryAction`/`secondaryAction` (un `Wrap` ya armado
  /// por el llamador).
  Widget encabezadoMaestro() {
    return RisegSectionHeader(
      title: 'SMARTPHONE',
      description: 'ART-000001 · Teléfonos',
      primaryAction: RisegButton(label: 'Editar', onPressed: () {}),
      secondaryAction: Wrap(
        spacing: 8,
        children: [
          RisegButton(label: 'Archivar', variant: RisegButtonVariant.ghost, onPressed: () {}),
          RisegButton(label: 'Eliminar físicamente (Maestro)', variant: RisegButtonVariant.danger, onPressed: () {}),
        ],
      ),
    );
  }

  Future<void> verificarTodoVisibleYAccesible(WidgetTester tester) async {
    expect(find.text('SMARTPHONE'), findsOneWidget, reason: 'el título nunca se esconde');
    expect(find.text('ART-000001 · Teléfonos'), findsOneWidget, reason: 'la descripción nunca se esconde');
    expect(find.text('Editar'), findsOneWidget);
    expect(find.text('Archivar'), findsOneWidget);
    expect(find.text('Eliminar físicamente (Maestro)'), findsOneWidget, reason: 'ninguna acción se trunca ni se esconde');

    for (final texto in ['Editar', 'Archivar', 'Eliminar físicamente (Maestro)']) {
      await tester.ensureVisible(find.text(texto));
      expect(find.text(texto).hitTestable(), findsOneWidget, reason: '"$texto" debe seguir siendo interactivo, no solo estar en el árbol');
    }
  }

  group('RisegSectionHeader — responsive con 3 acciones (caso real Maestro)', () {
    testWidgets('con ancho suficiente: título y las 3 acciones en la misma línea, sin overflow', (tester) async {
      tester.view.physicalSize = const Size(1200, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpRiseg(tester, encabezadoMaestro());

      expect(tester.takeException(), isNull);
      await verificarTodoVisibleYAccesible(tester);

      // Con espacio de sobra, título y el primer botón de acciones
      // deben quedar en el mismo renglón — layout "actual" preservado
      // cuando cabe. Tolerancia generosa (no 1-2px): el botón tiene su
      // propio padding/decoración interno que desplaza su texto un
      // poco respecto al título; lo que importa es que estén en la
      // misma línea visual, no alineados al pixel exacto.
      final yTitulo = tester.getTopLeft(find.text('SMARTPHONE')).dy;
      final yEditar = tester.getTopLeft(find.text('Editar')).dy;
      expect((yTitulo - yEditar).abs(), lessThan(30), reason: 'título y acciones en la misma línea cuando hay espacio');
    });

    testWidgets(
      'con ancho reducido: las 3 acciones bajan a una segunda línea completa, título sigue visible, sin overflow',
      (tester) async {
        tester.view.physicalSize = const Size(420, 500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await pumpRiseg(tester, encabezadoMaestro());

        expect(tester.takeException(), isNull);
        await verificarTodoVisibleYAccesible(tester);

        // A este ancho las acciones ya no caben junto al título — deben
        // haber bajado de línea (Y mayor), nunca haberse truncado ni
        // desaparecido (ya verificado arriba).
        final yTitulo = tester.getTopLeft(find.text('SMARTPHONE')).dy;
        final yEditar = tester.getTopLeft(find.text('Editar')).dy;
        expect(yEditar, greaterThan(yTitulo + 4), reason: 'las acciones bajaron a una línea propia debajo del título');
      },
    );

    testWidgets('ancho extremadamente angosto: incluso las propias 3 acciones se reparten entre sí sin desbordar', (tester) async {
      tester.view.physicalSize = const Size(260, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpRiseg(tester, encabezadoMaestro());

      expect(tester.takeException(), isNull);
      await verificarTodoVisibleYAccesible(tester);
    });
  });

  testWidgets('sesión normal (menos acciones): título + 1 sola acción también responsive, sin overflow', (tester) async {
    tester.view.physicalSize = const Size(300, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpRiseg(
      tester,
      RisegSectionHeader(
        title: 'Agenda de documentos por emitir',
        primaryAction: RisegButton(label: 'Generar agenda', onPressed: () {}),
        secondaryAction: RisegButton(label: 'Crear documento manual', variant: RisegButtonVariant.ghost, onPressed: () {}),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Agenda de documentos por emitir'), findsOneWidget);
    expect(find.text('Generar agenda'), findsOneWidget);
    expect(find.text('Crear documento manual'), findsOneWidget);
  });

  testWidgets('título excepcionalmente largo se envuelve en vez de robarle espacio a las acciones', (tester) async {
    tester.view.physicalSize = const Size(500, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpRiseg(
      tester,
      RisegSectionHeader(
        title: 'Un título de expediente excepcionalmente largo que nunca debería empujar los botones fuera de pantalla',
        primaryAction: RisegButton(label: 'Editar', onPressed: () {}),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('excepcionalmente largo'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);
    expect(find.text('Editar').hitTestable(), findsOneWidget);
  });
}
