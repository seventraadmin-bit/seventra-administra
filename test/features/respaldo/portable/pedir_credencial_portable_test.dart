// Etapa 4D — el diálogo que pide la credencial de un paquete.
//
// Este archivo existe por un bug real encontrado al revisar el diff, no por
// completar cobertura. La primera versión preguntaba "¿con qué quieres
// abrirlo?" usando las dos acciones del diálogo compartido de RISEG ONE, y
// su acción secundaria cierra devolviendo `null`, exactamente igual que la
// Escape. Elegir "con la clave de recuperación" era indistinguible de
// cancelar: la puerta de la clave quedaba inalcanzable desde la interfaz.
//
// Y es LA puerta importante. La frase se olvida; la clave de recuperación
// está escrita en un papel. Si la única forma de entrar fuera la frase, el
// escenario que justifica toda esta etapa —la computadora se destruyó y de
// la frase nadie se acuerda— no tendría salida.

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/features/respaldo/presentation/widgets/portable_dialogs.dart';

void main() {
  /// Monta un botón que abre el diálogo y guarda lo que devuelva.
  Future<CredencialPortable? Function()> montar(WidgetTester tester, {Size tamano = const Size(1366, 768)}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    CredencialPortable? capturada;
    var respondio = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('es'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('es')],
        home: Scaffold(
          body: Builder(
            builder:
                (context) => ElevatedButton(
                  key: const Key('abrir'),
                  onPressed: () async {
                    capturada = await pedirCredencialPortable(context);
                    respondio = true;
                  },
                  child: const Text('abrir'),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('abrir')));
    await tester.pumpAndSettle();

    return () {
      expect(respondio, isTrue, reason: 'el diálogo tenía que haber devuelto algo');
      return capturada;
    };
  }

  testWidgets('se ofrecen LAS DOS puertas', (tester) async {
    await montar(tester);
    expect(find.byKey(const Key('portable_elegir_frase')), findsOneWidget);
    expect(find.byKey(const Key('portable_elegir_clave')), findsOneWidget);
  });

  testWidgets('por defecto pide la frase', (tester) async {
    final resultado = await montar(tester);

    await tester.enterText(find.byKey(const Key('portable_campo_frase')), 'la frase de la empresa');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    final credencial = resultado();
    expect(credencial?.frase, 'la frase de la empresa');
    expect(credencial?.clave, isNull);
  });

  testWidgets('LA CLAVE DE RECUPERACIÓN ES ALCANZABLE — el bug que este archivo blinda', (tester) async {
    final resultado = await montar(tester);

    await tester.tap(find.byKey(const Key('portable_elegir_clave')));
    await tester.pumpAndSettle();

    // El campo cambió de identidad, así que el texto anterior no puede
    // sobrevivir al cambio de puerta.
    expect(find.byKey(const Key('portable_campo_clave_recuperacion')), findsOneWidget);
    expect(find.byKey(const Key('portable_campo_frase')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('portable_campo_clave_recuperacion')),
      'RISEG-ABCD-EFGH-JKMN-PQRS-TVWX-YZ23-4567',
    );
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    final credencial = resultado();
    expect(
      credencial?.clave,
      'RISEG-ABCD-EFGH-JKMN-PQRS-TVWX-YZ23-4567',
      reason: 'si esto vuelve a fallar, quien perdió su frase se queda sin forma de entrar',
    );
    expect(credencial?.frase, isNull, reason: 'una clave de recuperación jamás puede viajar como si fuera la frase');
  });

  testWidgets('cambiar de puerta NO arrastra lo ya escrito', (tester) async {
    final resultado = await montar(tester);

    await tester.enterText(find.byKey(const Key('portable_campo_frase')), 'esto es una frase');
    await tester.tap(find.byKey(const Key('portable_elegir_clave')));
    await tester.pumpAndSettle();

    // Sin esto, se enviaría una frase como si fuera una clave de
    // recuperación y el usuario vería "no se pudo abrir" sin entender nada.
    await tester.enterText(find.byKey(const Key('portable_campo_clave_recuperacion')), 'RISEG-0000');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(resultado()?.clave, 'RISEG-0000');
  });

  testWidgets('en blanco no se responde: el diálogo sigue abierto', (tester) async {
    await montar(tester);

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('portable_elegir_frase')),
      findsOneWidget,
      reason: 'sin credencial no hay nada que intentar, así que no se cierra',
    );
  });

  testWidgets('cancelar no devuelve credencial', (tester) async {
    final resultado = await montar(tester);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(resultado(), isNull);
  });

  for (final ancho in [1024.0, 700.0, 500.0]) {
    testWidgets('las dos puertas caben a ${ancho.toInt()} px', (tester) async {
      await montar(tester, tamano: Size(ancho, 700));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('portable_elegir_clave')), findsOneWidget);
    });
  }
}
