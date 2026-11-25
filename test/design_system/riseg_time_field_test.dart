import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import 'test_harness.dart';

void main() {
  testWidgets('renderiza label y hora formateada', (tester) async {
    await pumpRiseg(
      tester,
      RisegTimeField(label: 'Hora de inicio', value: const TimeOfDay(hour: 8, minute: 30), onChanged: (_) {}),
    );

    expect(find.text('Hora de inicio'), findsOneWidget);
    expect(find.textContaining('8:30'), findsOneWidget);
  });

  testWidgets('tocar el campo abre el selector y confirmar dispara onChanged', (tester) async {
    TimeOfDay? seleccionada;
    await pumpRiseg(
      tester,
      RisegTimeField(
        label: 'Hora de inicio',
        value: const TimeOfDay(hour: 9, minute: 0),
        onChanged: (value) => seleccionada = value,
      ),
    );

    await tester.tap(find.byType(TextFormField));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(seleccionada, const TimeOfDay(hour: 9, minute: 0));
  });

  testWidgets('🚫 un mensaje de error LARGO no se corta a una línea', (
    tester,
  ) async {
    // 🚫 **LO ENCONTRÓ EL DUEÑO EN LA PRUEBA DE CIERRE DE C3 (25-nov-2026):** el error de la
    // hora de entrada salía como «…se deriva de ést…». `InputDecoration` trunca `errorText`
    // y `helperText` a **UNA** línea salvo que el tema diga otra cosa, así que se perdía la
    // mitad de la frase que explica qué hacer — y el campo parecía rechazar sin razón.
    //
    // Se prueba AQUÍ y sobre el TEMA porque le pasaba a todos los campos, no a este: el
    // arreglo vive en `inputDecorationTheme`, y una prueba sobre un solo widget dejaría a
    // los demás cortando en silencio.
    const largo =
        'La entrada del turno de día va entre las 05:00 y las 11:00. '
        'La hora de la plaza de noche se deriva de ésta.';

    await pumpRiseg(
      tester,
      SizedBox(
        width: 280,
        child: RisegTimeField(
          label: 'Hora de entrada del turno de día',
          value: const TimeOfDay(hour: 20, minute: 0),
          onChanged: (_) {},
          errorText: largo,
        ),
      ),
    );

    // EL TEXTO ENTERO ESTÁ, y el tema le deja tres líneas para caber: con una sola, el
    // renglón se recortaba con puntos suspensivos.
    expect(find.text(largo), findsOneWidget);
    expect(
      Theme.of(
        tester.element(find.byType(RisegTimeField)),
      ).inputDecorationTheme.errorMaxLines,
      3,
    );

    // Y NO DESBORDA: un error de maquetación haría fallar esta prueba sola.
    expect(tester.takeException(), isNull);
  });

  testWidgets('enabled: false no abre el selector', (tester) async {
    await pumpRiseg(
      tester,
      RisegTimeField(label: 'Hora', value: const TimeOfDay(hour: 9, minute: 0), onChanged: (_) {}, enabled: false),
    );

    await tester.tap(find.byType(TextFormField));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
  });
}
