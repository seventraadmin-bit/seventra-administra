import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'test_harness.dart';

void main() {
  group('quitar la fecha', () {
    testWidgets('el aspa sólo existe si el campo admite vaciarse', (
      tester,
    ) async {
      // SIN `alLimpiar` NO HAY ASPA: donde la fecha es obligatoria, un botón de limpiar es
      // una trampa que sólo sirve para recibir un 400.
      await pumpRiseg(
        tester,
        RisegDateField(
          label: 'Hasta (opcional)',
          value: DateTime(2026, 12, 31),
          onChanged: (_) {},
        ),
      );

      expect(find.byKey(const Key('riseg-date-field-limpiar')), findsNothing);
    });

    testWidgets('con fecha y con alLimpiar, el aspa la quita', (tester) async {
      // 🚫 **LO PIDIÓ EL DUEÑO EL 25-nov-2026**, y por una razón concreta: la ayuda del
      // campo «Hasta (opcional)» dice «déjalo vacío si no tiene fecha de fin» y, una vez
      // puesta, **no había forma de vaciarla** —el selector sólo avisa cuando eliges una—.
      var limpiada = false;

      await pumpRiseg(
        tester,
        RisegDateField(
          label: 'Hasta (opcional)',
          value: DateTime(2026, 12, 31),
          onChanged: (_) {},
          alLimpiar: () => limpiada = true,
        ),
      );

      await tester.tap(find.byKey(const Key('riseg-date-field-limpiar')));
      await tester.pumpAndSettle();

      expect(limpiada, isTrue);
    });

    testWidgets('sin fecha no hay nada que quitar', (tester) async {
      await pumpRiseg(
        tester,
        RisegDateField(
          label: 'Hasta (opcional)',
          value: null,
          onChanged: (_) {},
          alLimpiar: () {},
        ),
      );

      expect(find.byKey(const Key('riseg-date-field-limpiar')), findsNothing);
    });
  });

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
