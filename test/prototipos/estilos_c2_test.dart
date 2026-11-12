// EL ESCAPARATE DE ESTILOS **CORRE**, y eso es lo único que se le exige.
//
// No se mide su diseño —eso lo decide el dueño mirándolo— ni su contenido, que es
// inventado. Se mide que las seis vistas se pinten sin lanzar, porque el valor de una
// propuesta es que se pueda abrir: una página que revienta al cambiar de pestaña no se
// puede comparar con nada, y el dueño lo descubriría con el navegador abierto.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/features/usuarios/web/marca_seventra.dart';
import 'package:riseg_one/prototipos/estilos_c2.dart';

void main() {
  testWidgets('las seis vistas se pintan sin lanzar', (tester) async {
    // UNA VENTANA DE ESCRITORIO: la propuesta es para el navegador, y con 800×600 el
    // resumen fijo del estilo B no cabe y el `Row` desbordaría — que sería un fallo de la
    // prueba y no del diseño.
    tester.view.physicalSize = const Size(1700, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        home: const EscaparateDeEstilos(),
      ),
    );
    await tester.pumpAndSettle();

    for (final estilo in ['A · Documento', 'B · Pestañas']) {
      await tester.tap(find.text(estilo));
      await tester.pumpAndSettle();

      for (final pantalla in ['Listado', 'Expediente (vista)', 'Alta']) {
        await tester.tap(find.text(pantalla));
        await tester.pumpAndSettle();

        for (final modulo in ['Servicios', 'Clientes']) {
          await tester.tap(find.text(modulo).first);
          await tester.pumpAndSettle();

          // SI ALGUNA VISTA LANZARA, `pumpAndSettle` YA HABRÍA FALLADO. Esto afirma
          // además que se pintó algo: una vista vacía no sirve para elegir.
          expect(find.byType(Scaffold), findsWidgets);
        }
      }
    }
  });

  testWidgets('las pestañas del expediente del estilo B se mueven', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1700, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        home: const EscaparateDeEstilos(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('B · Pestañas'));
    await tester.pumpAndSettle();

    // Con la pestaña «Generales» puesta, el domicilio no se ve: es justamente lo que el
    // estilo B propone —no se ve más de un asunto a la vez—.
    expect(find.text('Circuito Centro Comercial 40'), findsNothing);

    await tester.tap(find.text('Domicilio operativo'));
    await tester.pumpAndSettle();

    expect(find.text('Circuito Centro Comercial 40'), findsOneWidget);
  });
}
