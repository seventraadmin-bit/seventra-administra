import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'test_harness.dart';

class _Row {
  const _Row(this.id, this.nombre);
  final String id;
  final String nombre;

  @override
  bool operator ==(Object other) => other is _Row && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

void main() {
  final columns = [
    RisegColumn<_Row>(label: 'ID', cellBuilder: (row) => Text(row.id)),
    RisegColumn<_Row>(label: 'NOMBRE', cellBuilder: (row) => Text(row.nombre)),
  ];
  const rows = [_Row('1', 'Sportium'), _Row('2', 'Grupo Alfa')];

  testWidgets('renderiza encabezados y todas las filas', (tester) async {
    await pumpRiseg(tester, RisegTableBase<_Row>(columns: columns, rows: rows));

    expect(find.text('ID'), findsOneWidget);
    expect(find.text('NOMBRE'), findsOneWidget);
    expect(find.text('Sportium'), findsOneWidget);
    expect(find.text('Grupo Alfa'), findsOneWidget);
  });

  testWidgets('rows vacío muestra emptyState y ninguna fila', (tester) async {
    await pumpRiseg(
      tester,
      RisegTableBase<_Row>(
        columns: columns,
        rows: const [],
        emptyState: const RisegEmptyState(title: 'Sin filas', message: 'mensaje'),
      ),
    );

    expect(find.text('Sin filas'), findsOneWidget);
    expect(find.text('Sportium'), findsNothing);
  });

  testWidgets('loading: true no renderiza filas y muestra progreso', (tester) async {
    await pumpRiseg(tester, RisegTableBase<_Row>(columns: columns, rows: rows, loading: true));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Sportium'), findsNothing);
  });

  testWidgets('onRowTap se llama con la fila correcta al tocarla', (tester) async {
    _Row? tapped;
    await pumpRiseg(
      tester,
      RisegTableBase<_Row>(columns: columns, rows: rows, onRowTap: (row) => tapped = row),
    );

    await tester.tap(find.text('Grupo Alfa'));
    await tester.pump();

    expect(tapped, const _Row('2', 'Grupo Alfa'));
  });

  testWidgets('sin onRowTap, las filas no son interactivas (sin InkWell)', (tester) async {
    await pumpRiseg(tester, RisegTableBase<_Row>(columns: columns, rows: rows));
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('selectedRow marca esa fila como seleccionada semánticamente', (tester) async {
    await pumpRiseg(
      tester,
      RisegTableBase<_Row>(
        columns: columns,
        rows: rows,
        onRowTap: (_) {},
        selectedRow: const _Row('2', 'Grupo Alfa'),
      ),
    );

    final semantics = tester.getSemantics(find.ancestor(
      of: find.text('Grupo Alfa'),
      matching: find.byType(Semantics),
    ).first);
    expect(semantics.hasFlag(SemanticsFlag.isSelected), isTrue);
  });
}
