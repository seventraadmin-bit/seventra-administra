// C4 · LOS PORTALES DE UN CLIENTE, con su contraseña cifrada.
//
// ## Qué se fija aquí
//
// Las reglas que el servidor impone y la pantalla **explica**, y una que sólo existe en la
// pantalla:
//
//  1. **tres permisos independientes**, y el que más se presta a confundir es el tercero:
//     quien administra portales **fija** la contraseña y puede no poder verla. Los botones
//     de Mostrar y Copiar salen apagados **con su porqué**, no escondidos;
//  2. **revelar FUNCIONA con el portal archivado** —consultar un acceso retirado es
//     legítimo— mientras corregirlo y cambiarle la contraseña se rechazan. Es la única
//     asimetría del ciclo de vida, y la que una prueba descuidada invertiría;
//  3. **Mostrar y Copiar son dos actos**, y cada uno manda **su** acto al servidor: el acto
//     decide el evento que queda en la bitácora, así que mandar siempre `mostrar` dejaría
//     la mitad de los hechos mal registrados;
//  4. 🚫 **en la web no se promete que el portapapeles se borre** (C4-3): el escritorio lo
//     borra a los 60 segundos y el navegador no lo garantiza, así que decirlo sería
//     prometer una protección que no existe;
//  5. **la contraseña no se precarga ni se enseña enmascarada con su largo real**, y una
//     vacía NO borra: borrarla es su propio acto, con su propio botón;
//  6. **el aviso de que observaciones no es para contraseñas**, que es el hueco por el que
//     en el escritorio acaban escritas donde las ve cualquiera.
//
// ⚠️ **La contraseña no viaja en ningún listado**, así que estas pruebas no pueden leerla
// de la fila: la piden por su ruta, que es la única que la trae.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/api/api_client_autenticado.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/auth_api.dart';
import 'package:riseg_one/core/auth/gestor_de_sesion.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/logging/app_logger.dart';
import 'package:riseg_one/core/trabajo_sin_guardar/guardia_de_salida.dart';
import 'package:riseg_one/features/comercial/web/datos/clientes_repositorio_http.dart';
import 'package:riseg_one/features/comercial/web/presentation/seccion_de_portales.dart';
import 'package:riseg_one/features/usuarios/web/marca_seventra.dart';

class _Almacen implements AlmacenSesionRemota {
  CredencialRemota? guardada;

  @override
  Future<CredencialRemota?> leer() async => guardada;

  @override
  Future<void> escribir(CredencialRemota credencial) async =>
      guardada = credencial;

  @override
  Future<void> borrar() async => guardada = null;
}

class _Pedida {
  _Pedida(this.metodo, this.url, this.cuerpo);

  final String metodo;
  final Uri url;
  final String cuerpo;

  Map<String, Object?> get json => jsonDecode(cuerpo) as Map<String, Object?>;
}

void main() {
  final config = ApiConfig.resolve(
    raw: 'http://localhost:5199',
  ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

  final t0 = DateTime.utc(2026, 11, 26, 12);

  const empresa = '0193f0a0-0000-7000-8000-000000000001';
  const clienteId = '0193f0a0-0000-7000-8000-0000000000c1';
  const portalId = '0193f0a0-0000-7000-8000-0000000000p1';

  /// Un cuerpo de error **con la forma plana que el servidor manda de verdad**: `code` y
  /// `message` al nivel superior. Con un sobre `error`, `ApiErrorParser` no los encuentra y
  /// la prueba de un camino de error probaría menos de lo que dice **sin fallar**.
  String elError(String codigo, String mensaje) =>
      jsonEncode({'code': codigo, 'message': mensaje});

  Map<String, Object?> elPortal({
    String id = portalId,
    String nombre = 'Portal de facturación',
    String tipo = 'billing',
    String? url = 'https://facturas.sportium.mx',
    String? usuario = 'riseg',
    String? observaciones,
    String estatus = 'active',
    bool tieneContrasena = true,
    String? cambiadaEl = '2026-11-20T18:00:00Z',
  }) => {
    'id': id,
    'name': nombre,
    'kind': tipo,
    'url': url,
    'username': usuario,
    'notes': observaciones,
    'status': estatus,
    'hasSecret': tieneContrasena,
    'secretUpdatedAt': tieneContrasena ? cambiadaEl : null,
    'updatedAt': '2026-11-20T18:00:00Z',
  };

  Future<(ApiClientAutenticado, List<_Pedida>)> cliente({
    List<Map<String, Object?>> portales = const [],
    http.Response? Function(_Pedida pedida)? responder,
  }) async {
    final pedidas = <_Pedida>[];

    final desnudo = ApiClient(
      config: config,
      cliente: MockClient((p) async {
        if (p.url.path.endsWith('/auth/login')) {
          return http.Response(
            jsonEncode({
              'accessToken': 'at_1',
              'accessExpiresAt': t0
                  .add(const Duration(minutes: 30))
                  .toIso8601String(),
              'refreshToken': 'rt_1',
              'refreshExpiresAt': t0
                  .add(const Duration(days: 14))
                  .toIso8601String(),
              'sessionId': '0193f0a0-0000-7000-8000-00000000aaaa',
              'identityId': '0193f0a0-0000-7000-8000-00000000bbbb',
              'displayName': 'Ana Torres',
              'email': 'ana@seventra.mx',
            }),
            200,
          );
        }

        final pedida = _Pedida(p.method, p.url, p.body);
        pedidas.add(pedida);

        if (responder?.call(pedida) case final propia?) return propia;

        if (p.url.path.endsWith('/portals')) {
          return http.Response(jsonEncode(portales), 200);
        }

        return http.Response('{}', 200);
      }),
      logger: AppLogger.console(),
    );

    final gestor = GestorDeSesion(
      api: AuthApi(desnudo),
      almacen: _Almacen(),
      logger: AppLogger.console(),
      ahora: () => t0,
    );

    addTearDown(gestor.dispose);
    await gestor.iniciarSesion(email: 'ana@seventra.mx', password: 'x');

    return (ApiClientAutenticado(cliente: desnudo, gestor: gestor), pedidas);
  }

  Future<List<_Pedida>> montar(
    WidgetTester tester, {
    List<Map<String, Object?>> portales = const [],
    bool puedeAdministrar = true,
    bool puedeRevelar = true,
    GuardiaDeSalida? guardia,
    http.Response? Function(_Pedida pedida)? responder,
    CopiaAlPortapapeles? copiar,
  }) async {
    tester.view.physicalSize = const Size(1600, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final (api, pedidas) = await cliente(
      portales: portales,
      responder: responder,
    );

    final elGuardia = guardia ?? GuardiaDeSalida();

    final router = GoRouter(
      initialLocation: '/comercial/clientes/$clienteId',
      routes: [
        GoRoute(
          path: '/comercial/clientes/:id',
          builder: (_, _) => Scaffold(
            body: SingleChildScrollView(
              child: SeccionDePortales(
                repositorio: ClientesRepositorioHttp(api),
                empresaId: empresa,
                clienteId: clienteId,
                puedeAdministrar: puedeAdministrar,
                puedeRevelar: puedeRevelar,
                guardia: elGuardia,
                // ⚠️ **EL PORTAPAPELES DE VERDAD NO SIRVE AQUÍ**, y no es comodidad: en
                // una prueba de widget no hay canal de plataforma, así que
                // `Clipboard.setData` no se comporta como en un navegador. Con la costura,
                // la prueba ejercita **los dos** caminos —copió y no pudo copiar—, que es
                // justo lo que no se podría medir de otra forma.
                copiarAlPortapapeles: copiar ?? (_) async {},
              ),
            ),
          ),
        ),
      ],
    );

    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: MarcaSeventra.tema(), routerConfig: router),
    );
    await tester.pumpAndSettle();

    return pedidas;
  }

  /// El `IconButton` que lleva este tooltip.
  ///
  /// ⚠️ `find.byTooltip` devuelve el `Tooltip`, que es **descendiente** del botón: hay que
  /// buscar su ancestro, o leerlo como `IconButton` estalla.
  IconButton botonConTooltip(WidgetTester tester, String tooltip) =>
      tester.widget<IconButton>(
        find
            .ancestor(
              of: find.byTooltip(tooltip),
              matching: find.byType(IconButton),
            )
            .first,
      );

  /// El campo que lleva esta etiqueta, **dentro de la hoja**.
  Finder campoDe(String etiqueta) => find
      .descendant(
        of: find
            .ancestor(
              of: find.descendant(
                of: find.byType(BottomSheet),
                matching: find.text(etiqueta),
              ),
              matching: find.byType(Column),
            )
            .first,
        matching: find.byType(TextField),
      )
      .first;

  Future<void> darElMotivo(
    WidgetTester tester,
    String motivo, {
    String confirmar = 'Guardar',
  }) async {
    await tester.enterText(find.byType(TextField).last, motivo);
    await tester.pumpAndSettle();
    await tester.tap(find.text(confirmar).last);
    await tester.pumpAndSettle();
  }

  // =========================================================================
  group('la lista', () {
    testWidgets('dice el tipo, el estatus, la contraseña y cuándo cambió', (
      tester,
    ) async {
      await montar(tester, portales: [elPortal()]);

      expect(find.text('Portal de facturación'), findsOneWidget);
      expect(find.text('Facturación'), findsOneWidget);
      expect(find.text('Activo'), findsOneWidget);
      expect(
        find.text('https://facturas.sportium.mx · Usuario: riseg'),
        findsOneWidget,
      );

      // 🔑 LA CONTRASEÑA SE DICE ENMASCARADA Y CON SU FECHA, que es lo único que de ella
      // se puede leer sin pedirla. La fecha importa: una de hace dos años es la primera
      // sospechosa cuando el portal deja de abrir.
      expect(
        find.text('Contraseña: •••• · se cambió el 20/nov/2026'),
        findsOneWidget,
      );
    });

    testWidgets('sin contraseña lo dice, y no finge que hay una', (
      tester,
    ) async {
      await montar(tester, portales: [elPortal(tieneContrasena: false)]);

      expect(find.text('Sin contraseña'), findsOneWidget);
      expect(find.textContaining('Contraseña: ••••'), findsNothing);
    });

    testWidgets('un tipo que esta build no conoce se enseña tal cual', (
      tester,
    ) async {
      // La misma regla que el estatus de un cliente: un `_ => 'Otro'` lo haría
      // indistinguible del que de verdad es «Otro», y nadie notaría que falta un caso.
      await montar(tester, portales: [elPortal(tipo: 'aduanas')]);

      expect(find.text('aduanas'), findsOneWidget);
      expect(find.text('Otro'), findsNothing);
    });

    testWidgets('sin portales lo dice, y explica para qué sirve esto', (
      tester,
    ) async {
      await montar(tester);

      expect(
        find.textContaining('por dónde se le sube una factura'),
        findsOneWidget,
      );
    });

    testWidgets('y la lista NO trae la contraseña, ni cifrada', (tester) async {
      // El servidor no la manda; esta prueba fija que la pantalla tampoco la pide para
      // dibujar la lista. Si algún día alguien «mejorara» la fila revelándola, aquí
      // aparecería una petición a `/reveal` que nadie pidió.
      final pedidas = await montar(tester, portales: [elPortal()]);

      expect(pedidas.where((p) => p.url.path.endsWith('/reveal')), isEmpty);
    });
  });

  // =========================================================================
  group('los tres permisos', () {
    testWidgets('sin administrar no hay añadir, corregir ni contraseña', (
      tester,
    ) async {
      await montar(
        tester,
        portales: [elPortal()],
        puedeAdministrar: false,
      );

      expect(find.text('Añadir portal'), findsNothing);
      expect(find.byTooltip('Corregir'), findsNothing);
      expect(find.byTooltip('Contraseña'), findsNothing);
      expect(find.byTooltip('Archivar'), findsNothing);

      // Y MOSTRAR SÍ: quien sólo consulta entra aquí justamente a eso.
      expect(botonConTooltip(tester, 'Mostrar la contraseña').onPressed, isNotNull);
    });

    testWidgets(
      'quien administra y NO puede revelar lo encuentra DICHO, no deducido',
      (tester) async {
        await montar(
          tester,
          portales: [elPortal()],
          puedeRevelar: false,
        );

        // Los dos botones apagados **con su porqué**, no escondidos: escondidos harían
        // pensar que la función no existe.
        expect(
          botonConTooltip(
            tester,
            'Ver la contraseña necesita un permiso aparte, que no tienes.',
          ).onPressed,
          isNull,
        );

        // Y la frase, que es la que evita el ticket de «guardé la contraseña y no la veo».
        expect(
          find.textContaining('Puedes guardar contraseñas y no verlas'),
          findsOneWidget,
        );

        // LO QUE SÍ PUEDE, sigue encendido.
        expect(botonConTooltip(tester, 'Contraseña').onPressed, isNotNull);
      },
    );

    testWidgets('sin contraseña guardada, revelar se apaga con otro porqué', (
      tester,
    ) async {
      await montar(tester, portales: [elPortal(tieneContrasena: false)]);

      expect(
        botonConTooltip(
          tester,
          'Este portal no tiene contraseña guardada.',
        ).onPressed,
        isNull,
      );
    });
  });

  // =========================================================================
  group('un portal ARCHIVADO', () {
    testWidgets('se revela, y NO se corrige ni se le cambia la contraseña', (
      tester,
    ) async {
      await montar(tester, portales: [elPortal(estatus: 'archived')]);

      expect(find.text('Archivado'), findsOneWidget);

      // 🔑 LA ASIMETRÍA ENTERA, EN UNA PRUEBA: revelar sí, cambiar no. Una prueba que sólo
      // midiera «archivado = todo apagado» invertiría justo la regla que el escritorio ya
      // tenía: consultar la contraseña de un acceso retirado es legítimo; fijarle una
      // nueva no significa nada.
      expect(botonConTooltip(tester, 'Mostrar la contraseña').onPressed, isNotNull);

      final porQueNo = 'Está archivado: reactívalo para poder cambiarlo.';

      expect(botonConTooltip(tester, porQueNo).onPressed, isNull);

      // Y reactivar siempre se puede: es la salida de un archivado.
      expect(botonConTooltip(tester, 'Reactivar').onPressed, isNotNull);
    });
  });

  // =========================================================================
  group('mostrar y copiar', () {
    testWidgets('mostrar manda su acto y enseña la contraseña', (tester) async {
      final pedidas = await montar(
        tester,
        portales: [elPortal()],
        responder: (p) => p.url.path.endsWith('/reveal')
            ? http.Response(jsonEncode({'password': 'la-del-portal'}), 200)
            : null,
      );

      await tester.tap(find.byTooltip('Mostrar la contraseña'));
      await tester.pumpAndSettle();

      final revelar = pedidas.firstWhere((p) => p.url.path.endsWith('/reveal'));

      expect(revelar.metodo, 'POST');
      expect(revelar.json['act'], 'mostrar');

      expect(find.text('la-del-portal'), findsOneWidget);
      expect(find.textContaining('Queda registrado que la viste'), findsOneWidget);

      // Y AL CERRAR SE VA: no queda en ningún campo de la pantalla, así que recargar la
      // vuelve a ocultar sin que nadie tenga que acordarse de limpiarla.
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();

      expect(find.text('la-del-portal'), findsNothing);
    });

    testWidgets('copiar manda OTRO acto, y no promete borrar el portapapeles', (
      tester,
    ) async {
      String? copiado;

      final pedidas = await montar(
        tester,
        portales: [elPortal()],
        responder: (p) => p.url.path.endsWith('/reveal')
            ? http.Response(jsonEncode({'password': 'la-del-portal'}), 200)
            : null,
        copiar: (texto) async => copiado = texto,
      );

      await tester.tap(find.byTooltip('Copiar la contraseña'));

      // ⚠️ **SE BOMBEA A MANO Y NO CON `pumpAndSettle`**, y es un hallazgo de escribir esta
      // prueba: `pumpAndSettle` **adelanta el reloj** hasta que no queda nada pendiente, así
      // que el aviso de éxito —que se retira solo a los pocos segundos— ya se fue cuando se
      // va a buscar. La prueba fallaba diciendo «no encontré el texto» con el texto
      // perfectamente puesto, que es el peor diagnóstico posible.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // EL ACTO DECIDE EL EVENTO: mandar siempre `mostrar` dejaría la mitad de los hechos
      // mal registrados en la bitácora, y nadie lo notaría desde la pantalla.
      expect(
        pedidas.firstWhere((p) => p.url.path.endsWith('/reveal')).json['act'],
        'copiar',
      );

      // Y LO QUE SE COPIÓ ES LA CONTRASEÑA, no su máscara ni su id.
      expect(copiado, 'la-del-portal');

      // 🚫 C4-3 · NO SE PROMETE UN BORRADO QUE EL NAVEGADOR NO GARANTIZA. El escritorio
      // borra el portapapeles a los 60 segundos; aquí decirlo sería prometer una
      // protección que no existe.
      expect(find.textContaining('Contraseña copiada'), findsOneWidget);
      expect(find.textContaining('60 segundos'), findsNothing);
      expect(find.textContaining('se borrará'), findsNothing);

      // Y COPIAR NO ABRE EL DIÁLOGO: la contraseña va al portapapeles y no a la pantalla.
      expect(find.text('la-del-portal'), findsNothing);

      // Se deja el árbol quieto para que el aviso no sobreviva a la prueba.
      await tester.pumpAndSettle();
    });

    testWidgets('si el navegador NO deja copiar, se dice — y no se dice «copiada»', (
      tester,
    ) async {
      // ⚠️ **EL FALLO QUE NO SE NOTA.** El navegador puede negar el portapapeles, y
      // entonces avisar «copiada» es mentir: la persona pega y aparece lo que tenía antes.
      // Y el mensaje no puede decir «no pasó nada», porque el servidor ya descifró y ya
      // dejó el evento: lo honesto es decir qué hacer en su lugar.
      await montar(
        tester,
        portales: [elPortal()],
        responder: (p) => p.url.path.endsWith('/reveal')
            ? http.Response(jsonEncode({'password': 'la-del-portal'}), 200)
            : null,
        copiar: (_) async => throw StateError('el navegador dijo no'),
      );

      await tester.tap(find.byTooltip('Copiar la contraseña'));

      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.textContaining('no dejó copiarla'), findsOneWidget);
      expect(find.textContaining('Usa Mostrar'), findsOneWidget);
      expect(find.textContaining('Contraseña copiada'), findsNothing);

      await tester.pumpAndSettle();
    });

    testWidgets('«se cifró con otra llave» sale tal cual, y dice qué hacer', (
      tester,
    ) async {
      await montar(
        tester,
        portales: [elPortal()],
        responder: (p) => p.url.path.endsWith('/reveal')
            ? http.Response(
                elError(
                  'contrasena_de_otra_llave',
                  'Esta contraseña se cifró con otra llave; hay que capturarla de nuevo.',
                ),
                409,
              )
            : null,
      );

      await tester.tap(find.byTooltip('Mostrar la contraseña'));
      await tester.pumpAndSettle();

      // ES EL MENSAJE DEL SERVIDOR, LITERAL, y es el mismo del escritorio: explica la
      // causa —esta base se cifró en otro sitio— y la salida, que es capturarla otra vez.
      expect(
        find.textContaining('se cifró con otra llave'),
        findsOneWidget,
      );
    });
  });

  // =========================================================================
  group('la contraseña', () {
    testWidgets('el panel NO precarga la que hay, y lo dice', (tester) async {
      await montar(tester, portales: [elPortal()]);

      await tester.tap(find.byTooltip('Contraseña'));
      await tester.pumpAndSettle();

      // 🚫 VACÍO, Y NO ENMASCARADA CON SU LARGO REAL: precargarla obligaría a revelarla
      // para poder dibujarla, y entonces abrir este panel sería un acto de revelar sin su
      // permiso y sin su evento.
      expect(tester.widget<TextField>(campoDe('Contraseña')).controller!.text, '');

      expect(
        find.textContaining('La que hay no se muestra aquí'),
        findsOneWidget,
      );
    });

    testWidgets('una vacía NO borra: se rechaza sin salir a la red', (
      tester,
    ) async {
      final pedidas = await montar(tester, portales: [elPortal()]);

      await tester.tap(find.byTooltip('Contraseña'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Para dejar el portal sin ninguna, bórrala'), findsOneWidget);

      // Y NO SE PIDIÓ NADA: el servidor también lo rechaza, pero gastar una petición para
      // que conteste 400 convierte un error de forma en un viaje.
      expect(pedidas.where((p) => p.url.path.endsWith('/secret')), isEmpty);
    });

    testWidgets('fijarla manda la contraseña en el CUERPO y recarga', (
      tester,
    ) async {
      final pedidas = await montar(tester, portales: [elPortal()]);

      await tester.tap(find.byTooltip('Contraseña'));
      await tester.pumpAndSettle();

      await tester.enterText(campoDe('Contraseña'), 'la-nueva');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar').last);
      await tester.pumpAndSettle();

      final fijar = pedidas.firstWhere((p) => p.url.path.endsWith('/secret'));

      expect(fijar.metodo, 'PUT');
      expect(fijar.json['password'], 'la-nueva');

      // 🚫 Y NO VA EN LA DIRECCIÓN: una ruta termina en el registro de acceso del servidor
      // y en el historial del navegador.
      expect(fijar.url.toString().contains('la-nueva'), isFalse);
    });

    testWidgets('borrarla pide confirmación y es su propio acto', (
      tester,
    ) async {
      final pedidas = await montar(tester, portales: [elPortal()]);

      await tester.tap(find.byTooltip('Contraseña'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Borrar la contraseña'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No se guarda ninguna anterior'),
        findsOneWidget,
      );

      await tester.tap(find.text('Borrar').last);
      await tester.pumpAndSettle();

      final borrar = pedidas.firstWhere(
        (p) => p.metodo == 'DELETE' && p.url.path.endsWith('/secret'),
      );

      expect(borrar.metodo, 'DELETE');
    });

    testWidgets('sin contraseña no se ofrece borrarla', (tester) async {
      await montar(tester, portales: [elPortal(tieneContrasena: false)]);

      await tester.tap(find.byTooltip('Contraseña'));
      await tester.pumpAndSettle();

      expect(find.text('Borrar la contraseña'), findsNothing);
      expect(find.text('Guardar la contraseña'), findsOneWidget);
    });
  });

  // =========================================================================
  group('el alta y la corrección', () {
    testWidgets('el alta manda nombre y tipo, y NUNCA una contraseña', (
      tester,
    ) async {
      final pedidas = await montar(tester);

      await tester.tap(find.text('Añadir portal'));
      await tester.pumpAndSettle();

      await tester.enterText(campoDe('Nombre'), 'Portal de proveedores');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Para qué sirve este portal').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Proveedores').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar').last);
      await tester.pumpAndSettle();

      final alta = pedidas.firstWhere(
        (p) => p.metodo == 'POST' && p.url.path.endsWith('/portals'),
      );

      expect(alta.json['name'], 'Portal de proveedores');
      expect(alta.json['kind'], 'suppliers');

      // 🚫 LA CONTRASEÑA NO ESTÁ EN ESTE FORMULARIO, y por eso no puede llegar aquí: con
      // ella dentro, «dejar el campo vacío significa no cambiarla» sería una regla que hay
      // que adivinar, y guardar el portal podría borrarla por accidente.
      expect(alta.json.containsKey('password'), isFalse);
    });

    testWidgets('sin tipo no sale a la red, y dice qué falta', (tester) async {
      final pedidas = await montar(tester);

      await tester.tap(find.text('Añadir portal'));
      await tester.pumpAndSettle();

      await tester.enterText(campoDe('Nombre'), 'Portal sin tipo');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar').last);
      await tester.pumpAndSettle();

      expect(find.text('Elige para qué sirve este portal.'), findsOneWidget);
      expect(
        pedidas.where((p) => p.metodo == 'POST' && p.url.path.endsWith('/portals')),
        isEmpty,
      );
    });

    testWidgets('el formulario avisa de que observaciones no es para contraseñas', (
      tester,
    ) async {
      // 🚫 EL HUECO QUE EL ESCRITORIO DEJA ABIERTO: ahí este campo es donde la contraseña
      // acaba cuando el sistema no ofrece otro sitio, y entonces la ve cualquiera que
      // pueda leer el portal. Ahora hay un sitio, y el aviso dice cuál.
      await montar(tester);

      await tester.tap(find.text('Añadir portal'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No escribas aquí la contraseña'),
        findsOneWidget,
      );
    });

    testWidgets('corregir pide motivo y sólo manda lo que cambió', (
      tester,
    ) async {
      final pedidas = await montar(tester, portales: [elPortal()]);

      await tester.tap(find.byTooltip('Corregir'));
      await tester.pumpAndSettle();

      await tester.enterText(campoDe('Nombre'), 'Portal de facturas');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar').last);
      await tester.pumpAndSettle();

      await darElMotivo(tester, 'Le cambiaron el nombre');

      final patch = pedidas.firstWhere((p) => p.metodo == 'PATCH');

      expect(patch.json['reason'], 'Le cambiaron el nombre');
      expect(patch.json['name'], 'Portal de facturas');

      // SÓLO LO QUE CAMBIÓ: el servidor rechaza un `PATCH` que no cambia nada, así que
      // mandar el cuerpo completo haría que guardar sin tocar nada respondiera un error.
      expect(patch.json.containsKey('kind'), isFalse);
      expect(patch.json.containsKey('url'), isFalse);
    });
  });

  // =========================================================================
  group('archivar y reactivar', () {
    testWidgets('archivar pide motivo, avisa de qué NO hace, y manda el estatus', (
      tester,
    ) async {
      final pedidas = await montar(tester, portales: [elPortal()]);

      await tester.tap(find.byTooltip('Archivar'));
      await tester.pumpAndSettle();

      // EL AVISO DICE LO QUE ARCHIVAR **NO** HACE, que es lo que nadie adivina: ni borra
      // ni esconde, y mostrar la contraseña sigue funcionando.
      expect(find.textContaining('Archivar NO lo borra'), findsOneWidget);
      expect(find.textContaining('mostrar la que tiene, sí'), findsOneWidget);

      await darElMotivo(tester, 'Ya no se usa', confirmar: 'Archivar');

      final estatus = pedidas.firstWhere(
        (p) => p.metodo == 'PUT' && p.url.path.endsWith('/status'),
      );

      expect(estatus.json['status'], 'archived');
      expect(estatus.json['reason'], 'Ya no se usa');
    });

    testWidgets('reactivar manda active', (tester) async {
      final pedidas = await montar(
        tester,
        portales: [elPortal(estatus: 'archived')],
      );

      await tester.tap(find.byTooltip('Reactivar'));
      await tester.pumpAndSettle();

      await darElMotivo(tester, 'Volvemos a cobrar por aquí', confirmar: 'Reactivar');

      expect(
        pedidas
            .firstWhere(
              (p) => p.metodo == 'PUT' && p.url.path.endsWith('/status'),
            )
            .json['status'],
        'active',
      );
    });
  });
}
