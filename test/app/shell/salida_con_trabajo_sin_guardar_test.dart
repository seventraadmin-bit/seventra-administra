// D-56 · EL TRABAJO SIN GUARDAR NO SE TIRA POR CAMBIAR DE DIRECCIÓN.
//
// ## Qué cubre este archivo, y qué no
//
// Hay **cuatro** formas de tirar lo que alguien escribió, y cada una se para en su capa:
//
//  · **cambia la dirección** —atrás, una pestaña, cancelar, un enlace pegado—: el `onExit`
//    de la ruta. **Es lo que se prueba aquí.**
//  · **cambiar de empresa**: no cambia la dirección, así que pregunta el portón. Lo fija
//    `selector_y_menu_de_empresa_test.dart`.
//  · **recargar** y **cerrar la pestaña**: `beforeunload`, que es del navegador. Aquí se
//    prueba **la decisión** —`hayQueFrenarLaSalida`—, porque el diálogo del navegador no
//    existe en la VM. Las dos situaciones se comprueban **en pantalla**, y están en la
//    lista de cierre de C1.
//
// ## Por qué con el router de verdad y no llamando a `seguroDeSalir`
//
// Porque lo que se podría romper no es la función: es **que esté enganchada donde debe**.
// Un `onExit` puesto en la `ShellRoute` compila, no se llama nunca y no avisa; una ruta
// detrás del comodín nunca casa. Las dos averías pasarían una prueba de la función suelta
// y se verían en el primer «atrás» de verdad.
//
// ## El «atrás» del navegador, simulado donde de verdad entra
//
// `tester.binding.handlePushRoute` es **el mismo canal por el que la plataforma avisa de
// que la dirección cambió**, y es por donde entra el botón «atrás» en la web: el navegador
// mueve su historial y se lo dice a Flutter. No es un `go` disfrazado — un `go` lo pide la
// aplicación, y aquí lo pide el navegador, que es justo el camino que no pasaba por la
// pantalla.
//
// Lo que NO lleva esto es el historial del navegador de verdad, así que la entrada de más
// que queda al cancelar (ver `docs/diseno-d56-trabajo-sin-guardar.md` §1.2) se comprueba
// en pantalla, no aquí.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:riseg_one/app/shell/router_web.dart';
import 'package:riseg_one/core/company/aviso_de_salida.dart';
import 'package:riseg_one/core/company/guardia_de_salida.dart';
import 'package:riseg_one/core/company/permiso_company.dart';
import 'package:riseg_one/features/usuarios/web/marca_seventra.dart';

void main() {
  // Alguien que puede ver la estructura y el expediente de la empresa: es quien puede
  // abrir los dos formularios, y por tanto el único que puede tener algo que perder.
  //
  // `companySettingsRead` ABRE LA PESTAÑA y `companySettingsManage` deja escribir: sin el
  // primero el guardia del router mandaría esta sesión a Sucursales y la prueba mediría
  // otra cosa — pasó al escribirla.
  const permisos = {
    PermisoCompany.organizacionVer,
    PermisoCompany.companySettingsRead,
    PermisoCompany.companySettingsManage,
  };

  /// Monta el router con el guardia que se le pase, en la dirección del formulario.
  ///
  /// **El portón se sustituye por un recuadro**, y es deliberado: lo que se mide es el
  /// router. Montar el portón de verdad traería sesión, empresa, repositorios y nueve
  /// peticiones, y ninguna de las cuatro cosas que esta prueba afirma depende de ellas.
  Future<GoRouter> montar(
    WidgetTester tester, {
    required GuardiaDeSalida guardia,
    String desde = '/organizacion/empresa/editar',
  }) async {
    final router = construirRouterWeb(
      porton: const Scaffold(body: Text('el portón')),
      gestores: Listenable.merge([]),
      autoridad: () => (esMaestro: false, permisos: permisos),
      guardia: guardia,
      initialLocation: desde,
    );

    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: MarcaSeventra.tema(), routerConfig: router),
    );
    await tester.pumpAndSettle();

    expect(
      router.state.uri.path,
      desde,
      reason: 'el guardia del router no debería haber movido esta dirección',
    );

    return router;
  }

  /// Un formulario montado y sucio, con su nombre.
  GuardiaDeSalida conTrabajoSinGuardar([
    String nombre = 'el expediente de la empresa',
  ]) => GuardiaDeSalida()..registrar(() => true, queSePierde: () => nombre);

  /// El «atrás» del navegador: la plataforma avisa de una dirección nueva.
  Future<void> atras(WidgetTester tester, String aDonde) async {
    await tester.binding.handlePushRoute(aDonde);
    await tester.pumpAndSettle();
  }

  group('el botón «atrás» del navegador', () {
    testWidgets('con trabajo sin guardar PREGUNTA, y nombra qué tiene cambios', (
      tester,
    ) async {
      await montar(tester, guardia: conTrabajoSinGuardar());

      await atras(tester, '/organizacion/empresa');

      expect(find.text('¿Salir sin guardar?'), findsOneWidget);

      // ⚠️ EL NOMBRE SALE DEL FORMULARIO, no del router: es lo único que el router no
      // puede saber, y es lo que el dueño pidió el 26 de octubre de 2026 —«Tienes cambios
      // sin guardar en el expediente de la sucursal Centro»—.
      expect(
        find.text('Tienes cambios sin guardar en el expediente de la empresa.'),
        findsOneWidget,
      );

      // Y LOS DOS BOTONES, con las palabras aprobadas: la que se queda primero.
      expect(find.text('Seguir editando'), findsOneWidget);
      expect(find.text('Salir sin guardar'), findsOneWidget);
    });

    testWidgets('«Seguir editando» DEJA LA DIRECCIÓN donde estaba', (tester) async {
      // ES EL CORAZÓN DEL ASUNTO. Sin esto la pregunta sería decorativa: se contestaría
      // «no» y el trabajo se perdería igual.
      final router = await montar(tester, guardia: conTrabajoSinGuardar());

      await atras(tester, '/organizacion/empresa');
      await tester.tap(find.text('Seguir editando'));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, '/organizacion/empresa/editar');
    });

    testWidgets('«Salir sin guardar» sale', (tester) async {
      // EL CONTRAPUNTO, Y NO SOBRA: un `onExit` que devolviera siempre `false` pasaría la
      // prueba de arriba y dejaría a cualquiera **encerrado en el formulario**, sin forma
      // de salir más que recargando.
      final router = await montar(tester, guardia: conTrabajoSinGuardar());

      await atras(tester, '/organizacion/empresa');
      await tester.tap(find.text('Salir sin guardar'));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, '/organizacion/empresa');
    });

    testWidgets('sin trabajo sin guardar NO pregunta nada', (tester) async {
      // EL CASO FRECUENTE. Una pregunta que sale siempre se contesta sin leerla, y
      // entonces deja de proteger.
      final router = await montar(tester, guardia: GuardiaDeSalida());

      await atras(tester, '/organizacion/empresa');

      expect(find.text('¿Salir sin guardar?'), findsNothing);
      expect(router.state.uri.path, '/organizacion/empresa');
    });
  });

  group('qué direcciones preguntan', () {
    testWidgets('el expediente de una sucursal también, con SU nombre', (tester) async {
      // LA SEGUNDA RUTA CON FORMULARIO, y el nombre dice cuál: aquí sí hace falta, porque
      // hay una sucursal por fila y «el expediente» a secas no diría de qué.
      final router = await montar(
        tester,
        guardia: conTrabajoSinGuardar('el expediente de la sucursal Centro'),
        desde: '/organizacion/sucursales/0193f0a0-0000-7000-8000-0000000000c1/expediente',
      );

      await atras(tester, '/organizacion/sucursales');

      expect(
        find.text(
          'Tienes cambios sin guardar en el expediente de la sucursal Centro.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Seguir editando'));
      await tester.pumpAndSettle();

      expect(
        router.state.uri.path,
        '/organizacion/sucursales/0193f0a0-0000-7000-8000-0000000000c1/expediente',
      );
    });

    testWidgets('una dirección SIN formulario no pregunta, aunque el guardia esté sucio', (
      tester,
    ) async {
      // ⚠️ ESTO ES LO QUE FIJA QUE EL `onExit` ESTÁ SÓLO DONDE DEBE, y no en el comodín.
      //
      // Y la trampa es fina: la ruta comodín **también** dispararía `onExit` —
      // `matchedLocation` entra en la igualdad de `RouteMatch`, así que cada dirección es
      // un match distinto—. Si estuviera ahí, moverse entre pestañas con un panel sucio
      // abierto preguntaría «¿salir sin guardar?» sin que nadie salga de ningún
      // formulario.
      final router = await montar(
        tester,
        guardia: conTrabajoSinGuardar(),
        desde: '/organizacion/sucursales',
      );

      await atras(tester, '/organizacion/areas');

      expect(find.text('¿Salir sin guardar?'), findsNothing);
      expect(router.state.uri.path, '/organizacion/areas');
    });

    testWidgets('moverse DENTRO del formulario no pregunta', (tester) async {
      // La dirección cambia —de `…/empresa/editar` a sí misma con otra forma no, pero de
      // la ficha al formulario sí—, y entrar nunca puede perder nada: lo que `onExit`
      // vigila es la salida.
      final router = await montar(
        tester,
        guardia: conTrabajoSinGuardar(),
        desde: '/organizacion/empresa',
      );

      router.go('/organizacion/empresa/editar');
      await tester.pumpAndSettle();

      expect(find.text('¿Salir sin guardar?'), findsNothing);
      expect(router.state.uri.path, '/organizacion/empresa/editar');
    });
  });

  group('la navegación de la propia aplicación', () {
    testWidgets('una pestaña del menú pregunta igual que el navegador', (tester) async {
      // ES EL MISMO `onExit` para los dos caminos, y por eso basta una pieza: la pantalla
      // dejó de preguntar y nadie se quedó sin protección.
      final router = await montar(tester, guardia: conTrabajoSinGuardar());

      router.go('/organizacion/sucursales');
      await tester.pumpAndSettle();

      expect(find.text('¿Salir sin guardar?'), findsOneWidget);

      await tester.tap(find.text('Seguir editando'));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, '/organizacion/empresa/editar');
    });

    testWidgets('guardar y volver a la ficha NO pregunta', (tester) async {
      // ⚠️ LA PREGUNTA FALSA QUE HABRÍA PARECIDO UN ERROR DE GUARDADO. Guardar cierra el
      // formulario navegando a la ficha, así que pasa por `onExit`; si el formulario
      // siguiera diciendo «sucio» en ese instante, saldría «¿salir sin guardar?» justo
      // después de un guardado correcto.
      //
      // No pasa porque el formulario se limpia ANTES de avisar al llamador, y esta prueba
      // lo sostiene desde fuera: el guardia limpio en el momento de navegar.
      var sucio = true;
      final guardia = GuardiaDeSalida()
        ..registrar(() => sucio, queSePierde: () => 'el expediente de la empresa');

      final router = await montar(tester, guardia: guardia);

      // Lo que hace el guardado: deja el formulario limpio y entonces navega.
      sucio = false;
      router.go('/organizacion/empresa');
      await tester.pumpAndSettle();

      expect(find.text('¿Salir sin guardar?'), findsNothing);
      expect(router.state.uri.path, '/organizacion/empresa');
    });
  });

  group('recargar y cerrar la pestaña', () {
    // LAS DOS SON EL MISMO EVENTO y el navegador no dice cuál: `beforeunload` no lo
    // distingue, y desde dentro de la página no hay forma de saberlo. Así que lo que se
    // prueba es **la decisión**, que es lo único que puede equivocarse —alguien podría
    // invertirla—; el diálogo del navegador va a la prueba en pantalla.

    test('con trabajo sin guardar se frena la salida', () {
      expect(hayQueFrenarLaSalida(conTrabajoSinGuardar()), isTrue);
    });

    test('sin trabajo sin guardar se deja ir', () {
      // Y ÉSTE ES EL LADO CARO SI SE EQUIVOCA: un aviso pegado haría que no se pudiera
      // recargar la página en toda la sesión, y parecería un cuelgue del producto.
      expect(hayQueFrenarLaSalida(GuardiaDeSalida()), isFalse);
    });
  });
}
