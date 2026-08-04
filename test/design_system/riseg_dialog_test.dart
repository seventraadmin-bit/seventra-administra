import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'test_harness.dart';

void main() {
  testWidgets('showConfirmation retorna true al confirmar y false al cancelar', (tester) async {
    bool? result;

    await pumpRiseg(
      tester,
      Builder(
        builder: (context) => RisegButton(
          label: 'Abrir',
          onPressed: () async {
            result = await RisegDialog.showConfirmation(
              context: context,
              title: 'Título',
              message: 'Mensaje',
              confirmLabel: 'Confirmar',
              cancelLabel: 'Cancelar',
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Título'), findsOneWidget);

    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('cancelar retorna false', (tester) async {
    bool? result;

    await pumpRiseg(
      tester,
      Builder(
        builder: (context) => RisegButton(
          label: 'Abrir',
          onPressed: () async {
            result = await RisegDialog.showConfirmation(
              context: context,
              title: 'Título',
              message: 'Mensaje',
              confirmLabel: 'Confirmar',
              cancelLabel: 'Cancelar',
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('con onConfirm async, muestra loading y bloquea cancelar hasta resolver', (tester) async {
    await pumpRiseg(
      tester,
      Builder(
        builder: (context) => RisegButton(
          label: 'Abrir',
          onPressed: () => RisegDialog.showConfirmation(
            context: context,
            title: 'Eliminar registro',
            message: 'Mensaje',
            confirmLabel: 'Eliminar',
            cancelLabel: 'Cancelar',
            destructive: true,
            onConfirm: () => Future.delayed(const Duration(milliseconds: 200)),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Eliminar'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final cancelButton = tester.widget<TextButton>(find.ancestor(
      of: find.text('Cancelar'),
      matching: find.byType(TextButton),
    ));
    expect(cancelButton.onPressed, isNull);

    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
}
