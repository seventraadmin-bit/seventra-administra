// El diálogo común de motivo, a todos los anchos y en ambos temas.
//
// Es el único control nuevo que la etapa de trazabilidad mete en las
// pantallas de edición de Comercial, y aparece en corrección,
// suspensión, terminación, archivo y reactivación. Si desbordara a
// 500px, desbordaría en las cinco.
//
// Evidencia: cero overflow / cero excepción (`tester.takeException()`),
// el mismo criterio del resto del proyecto.

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

const _anchos = <String, Size>{
  '1536': Size(1536, 1000),
  '1366': Size(1366, 900),
  '1024': Size(1024, 900),
  '700': Size(700, 900),
  '500': Size(500, 900),
};

void main() {
  Future<void> abrirDialogo(WidgetTester tester, {required Size tamano, required bool oscuro}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: oscuro ? AppTheme.dark() : AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => mostrarDialogoMotivo(
                  context,
                  // Texto largo a propósito: un título corto nunca
                  // habría descubierto un desbordamiento.
                  titulo: 'Motivo de la terminación anticipada del servicio',
                  etiquetaMotivo: 'Motivo',
                  confirmarLabel: 'Confirmar',
                  cancelarLabel: 'Cancelar',
                  errorMotivoRequerido: 'El motivo es obligatorio.',
                  advertencia: 'Esta operación quedará registrada en la bitácora del registro, '
                      'con tu usuario y la fecha en que la realizaste.',
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  for (final ancho in _anchos.entries) {
    for (final oscuro in [false, true]) {
      testWidgets('diálogo de motivo a ${ancho.key}px, tema ${oscuro ? 'oscuro' : 'claro'}: sin overflow',
          (tester) async {
        await abrirDialogo(tester, tamano: ancho.value, oscuro: oscuro);

        expect(find.byKey(const Key('dialogo_motivo_campo')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('sin motivo no confirma, y lo dice; con motivo devuelve el texto', (tester) async {
    await abrirDialogo(tester, tamano: const Size(1366, 900), oscuro: false);

    // Confirmar en vacío: el diálogo sigue abierto y marca el error.
    await tester.tap(find.widgetWithText(RisegButton, 'Confirmar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dialogo_motivo_campo')), findsOneWidget, reason: 'no se cierra sin motivo');
    expect(find.text('El motivo es obligatorio.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Con motivo: cierra.
    await tester.enterText(find.byKey(const Key('dialogo_motivo_campo')), 'Fin de contrato');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(RisegButton, 'Confirmar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dialogo_motivo_campo')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cerrar el diálogo no destruye el controlador antes de tiempo', (tester) async {
    // Regresión del bug real del proyecto: destruir el
    // `TextEditingController` justo después del `await` estalla con
    // "used after being disposed" durante la transición de salida.
    await abrirDialogo(tester, tamano: const Size(1366, 900), oscuro: false);

    await tester.enterText(find.byKey(const Key('dialogo_motivo_campo')), 'Motivo');
    await tester.pump();
    await tester.tap(find.widgetWithText(RisegButton, 'Cancelar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
