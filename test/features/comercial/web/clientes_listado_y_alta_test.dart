// C1 · EL LISTADO Y EL ALTA DE CLIENTES.
//
// ## Qué se fija aquí, y por qué estas cosas y no otras
//
// Tres propiedades que se rompen en silencio si nadie las mira:
//
//  1. **los filtros los aplica el SERVIDOR.** Clientes no tiene paginación, así que
//     filtrar en la pantalla significaría traerse la cartera entera para enseñar tres
//     filas. Lo que se comprueba es que lo elegido **viaje en la petición**, porque un
//     filtro que se aplicara en memoria funcionaría igual con diez clientes y se notaría
//     con mil;
//  2. **el buscador no pide por tecla.** Va al servidor, así que escribir «Sportium»
//     serían ocho peticiones cuyas respuestas pueden llegar desordenadas: la de «Spo»
//     después de la de «Sportium» dejaría la lista enseñando una búsqueda que ya nadie
//     está haciendo;
//  3. **el alta son DOS peticiones y la segunda puede fallar sin deshacer la primera.**
//     Es la regla del dueño: «si el logotipo falla, el cliente queda creado», y la
//     pantalla lo dice. Sin prueba, lo primero que se simplifica al refactorizar es el
//     camino del error.
//
// ## Lo que NO está aquí
//
// Que ningún formulario de la web se quede sin registrarse en el guardia lo fija el
// candado de `test/app/shell/guardia_cubre_los_formularios_test.dart`. Que la pregunta
// salga y que cancelar deje la dirección quieta lo fija
// `test/app/shell/salida_con_trabajo_sin_guardar_test.dart`, con el router de verdad.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/app/shell/apartados_web.dart' show CapacidadesDeModulo;
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/api/api_client_autenticado.dart';
import 'package:riseg_one/core/archivos/elegir_logotipo.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/auth_api.dart';
import 'package:riseg_one/core/auth/gestor_de_sesion.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/design_system/design_system_web.dart';
import 'package:riseg_one/core/fechas/dia_de_negocio.dart';
import 'package:riseg_one/core/logging/app_logger.dart';
import 'package:riseg_one/core/trabajo_sin_guardar/guardia_de_salida.dart';
import 'package:riseg_one/features/comercial/web/datos/clientes_repositorio_http.dart';
import 'package:riseg_one/features/comercial/web/modelos/cliente.dart';
import 'package:riseg_one/features/comercial/web/presentation/clientes_web_screen.dart';
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

/// Una petición tal como la vio el transporte. **Se guarda el método y la URL**, que es
/// lo que distingue «pidió con filtro» de «pidió todo y filtró después».
class _Pedida {
  _Pedida(this.metodo, this.url, this.cuerpo);

  final String metodo;
  final Uri url;
  final String cuerpo;
}

void main() {
  final config = ApiConfig.resolve(
    raw: 'http://localhost:5199',
  ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

  final t0 = DateTime.utc(2026, 10, 26, 12);

  const empresa = '0193f0a0-0000-7000-8000-000000000001';
  const clienteId = '0193f0a0-0000-7000-8000-0000000000c1';

  Map<String, Object?> fila({
    required String id,
    required String codigo,
    required String nombre,
    String estatus = 'active',
    String? ubicacion = 'Cuautitlán Izcalli, Estado de México',
    int activos = 2,
    int suspendidos = 0,
    String? observaciones,
  }) => {
    'id': id,
    'code': codigo,
    'commercialName': nombre,
    'status': estatus,
    'startedOn': '2025-03-01',
    'notes': observaciones,
    'updatedAt': '2026-10-20T18:00:00Z',
    'location': ubicacion,
    'activeServices': activos,
    'suspendedServices': suspendidos,
  };

  final sportium = fila(
    id: clienteId,
    codigo: 'CLI-000004',
    nombre: 'Sportium',
  );

  final terminado = fila(
    id: '0193f0a0-0000-7000-8000-0000000000c2',
    codigo: 'CLI-000009',
    nombre: 'Lavandería Ríos',
    estatus: 'terminated',
    ubicacion: null,
    activos: 0,
  );

  /// El cliente HTTP, con la bitácora de lo que se pidió y una respuesta que se puede
  /// cambiar por prueba.
  Future<(ApiClientAutenticado, List<_Pedida>)> cliente({
    List<Map<String, Object?>>? cartera,
    http.Response Function(_Pedida pedida)? responder,
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

        if (responder != null) return responder(pedida);

        return http.Response(
          jsonEncode(cartera ?? [sportium, terminado]),
          200,
        );
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

  const todo = CapacidadesDeModulo(
    puedeVer: true,
    puedeCrear: true,
    puedeModificar: true,
    puedeArchivar: true,
  );

  const soloLeer = CapacidadesDeModulo(
    puedeVer: true,
    puedeCrear: false,
    puedeModificar: false,
    puedeArchivar: false,
  );

  /// Una ventana ALTA, y hace falta: los botones del pie del panel caen fuera de los
  /// 600×800 por omisión, y un `tap` sobre algo que no se ve **no hace nada y no se
  /// queja**.
  void ventanaAlta(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;

    addTearDown(tester.view.reset);
  }

  /// Monta Clientes **dentro de un router de verdad**: el panel de alta lleva el mixin
  /// que lo cierra cuando cambia la dirección, y sin router eso no existe.
  Future<List<_Pedida>> montar(
    WidgetTester tester, {
    GuardiaDeSalida? guardia,
    CapacidadesDeModulo capacidades = todo,
    List<Map<String, Object?>>? cartera,
    http.Response Function(_Pedida pedida)? responder,
    SelectorDeLogotipo? selector,
  }) async {
    ventanaAlta(tester);

    final (api, pedidas) = await cliente(
      cartera: cartera,
      responder: responder,
    );

    final router = GoRouter(
      initialLocation: '/comercial/clientes',
      routes: [
        GoRoute(
          path: '/comercial/:pestana',
          builder: (_, _) => ClientesWebScreen(
            repositorio: ClientesRepositorioHttp(api),
            empresaId: empresa,
            capacidades: capacidades,
            guardia: guardia ?? GuardiaDeSalida(),
            elegirUnLogotipo: selector ?? elegirLogotipo,
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

  /// El campo que lleva esta etiqueta, **dentro de la hoja**.
  ///
  /// ⚠️ **SE ACOTA A LA HOJA Y NO SE BUSCA EN TODA LA PANTALLA**, y conviene decir por
  /// qué: «Nombre comercial» es a la vez el rótulo de una columna de la tabla y la
  /// etiqueta de un campo del panel. Sin acotar, el buscador encuentra primero el rótulo
  /// —que no tiene ningún `TextField` debajo— y la prueba falla con «Bad state: No
  /// element», que no se parece en nada a su causa. Pasó al escribirla.
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

  /// Las peticiones al listado, que son las únicas con las que se razona aquí.
  List<_Pedida> listados(List<_Pedida> pedidas) => pedidas
      .where((p) => p.metodo == 'GET' && p.url.path.endsWith('/clients'))
      .toList();

  // =========================================================================
  group('los filtros los aplica el servidor', () {
    testWidgets('al abrir se pide la cartera sin filtrar', (tester) async {
      final pedidas = await montar(tester);

      final primera = listados(pedidas).single;

      // `endsWith` Y NO IGUALDAD: la ruta lleva el prefijo de versión de la API, y
      // fijarlo aquí haría que esta prueba se rompiera el día que cambie —que es cosa
      // del guardia del prefijo, no de Clientes—.
      expect(primera.url.path, endsWith('/companies/$empresa/clients'));
      expect(
        primera.url.queryParameters,
        isEmpty,
        reason:
            'sin filtros no se manda `status=`, `query=` ni `withServices=`: un '
            'parámetro vacío haría que el servidor buscara la cadena vacía',
      );
    });

    testWidgets('«Finalizados» pide status=terminated al servidor', (
      tester,
    ) async {
      final pedidas = await montar(tester);

      await tester.tap(find.text('Finalizados'));
      await tester.pumpAndSettle();

      // ⚠️ EL CHIP SÍ LO PUEDE EXPRESAR EL SERVIDOR cuando es UN estatus: «Finalizados»
      // son los terminados y nada más, así que viaja. Lo que no cabe en `status` es
      // «Vigentes», que son dos.
      expect(listados(pedidas).last.url.queryParameters['status'], 'terminated');
    });

    testWidgets('un estatus concreto manda ese estatus, no el del chip', (
      tester,
    ) async {
      final pedidas = await montar(tester);

      await tester.tap(find.text('Todos los estatus'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suspendido').last);
      await tester.pumpAndSettle();

      expect(listados(pedidas).last.url.queryParameters['status'], 'suspended');
    });

    testWidgets('el filtro de servicios viaja como withServices', (
      tester,
    ) async {
      final pedidas = await montar(tester);

      await tester.tap(find.text('Todos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sin servicios').last);
      await tester.pumpAndSettle();

      expect(
        listados(pedidas).last.url.queryParameters['withServices'],
        'false',
        reason: '«Sin servicios» es `false`, no la ausencia del parámetro',
      );
    });

    testWidgets('el buscador NO pide una vez por tecla', (tester) async {
      final pedidas = await montar(tester);

      final antes = listados(pedidas).length;

      // SE ESCRIBE Y NO SE ESPERA: `enterText` entrega el texto completo, así que para
      // ver el efecto del temporizador se avanza menos de lo que dura.
      await tester.enterText(
        find.byType(TextField).first,
        'Sportium',
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        listados(pedidas).length,
        antes,
        reason: 'todavía no ha pasado la espera: no se pide nada',
      );

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final despues = listados(pedidas);

      expect(despues.length, antes + 1, reason: 'una sola petición, al parar');
      expect(despues.last.url.queryParameters['query'], 'Sportium');
    });

    testWidgets('«Limpiar filtros» vuelve a pedir sin filtros, y se apaga', (
      tester,
    ) async {
      final pedidas = await montar(tester);

      await tester.tap(find.text('Todos los estatus'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suspendido').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Limpiar filtros'));
      await tester.pumpAndSettle();

      expect(listados(pedidas).last.url.queryParameters, isEmpty);

      // Y SIN FILTROS EL BOTÓN SE APAGA: uno que no hace nada al pulsarlo enseña que
      // los botones no hacen nada.
      final limpiar = tester.widget<RisegButton>(
        find.widgetWithText(RisegButton, 'Limpiar filtros'),
      );

      expect(limpiar.onPressed, isNull);
    });
  });

  // =========================================================================
  group('el chip «Vigentes» es lo único que filtra la pantalla', () {
    testWidgets('con el chip en Vigentes no se enseña el terminado', (
      tester,
    ) async {
      await montar(tester);

      // EL SERVIDOR DEVOLVIÓ LOS DOS —`status` no puede expresar «activo o
      // suspendido»— y la pantalla esconde el finalizado.
      expect(find.text('Sportium'), findsOneWidget);
      expect(find.text('Lavandería Ríos'), findsNothing);
    });

    testWidgets('con el chip en Finalizados se enseña el terminado', (
      tester,
    ) async {
      // AQUÍ EL SERVIDOR YA FILTRÓ, así que la respuesta trae sólo el terminado.
      await montar(tester, cartera: [terminado]);

      await tester.tap(find.text('Finalizados'));
      await tester.pumpAndSettle();

      expect(find.text('Lavandería Ríos'), findsOneWidget);
    });

    testWidgets('sin ubicación dice «No registrada», nunca vacío', (
      tester,
    ) async {
      await montar(tester, cartera: [terminado]);

      await tester.tap(find.text('Finalizados'));
      await tester.pumpAndSettle();

      // AUSENCIA NO ES CADENA VACÍA: una celda en blanco se lee como un dato que se
      // perdió, no como un cliente sin domicilio de referencia.
      expect(find.text('No registrada'), findsOneWidget);
    });

    testWidgets('un estatus que esta build no conoce se enseña tal cual', (
      tester,
    ) async {
      // ⚠️ EL CASO DEL SERVIDOR MÁS NUEVO. Con un `_ => activo` por omisión, este
      // cliente se pintaría como activo sin serlo, y nadie lo notaría.
      await montar(
        tester,
        cartera: [
          fila(
            id: clienteId,
            codigo: 'CLI-000050',
            nombre: 'Marca Nueva',
            estatus: 'dormant',
          ),
        ],
      );

      expect(find.text('dormant'), findsOneWidget);
      expect(find.text('Activo'), findsNothing);
    });
  });

  // =========================================================================
  group('lo que no se puede hacer no se muestra', () {
    testWidgets('sin `manage` no hay botón de alta, ni en el estado vacío', (
      tester,
    ) async {
      await montar(tester, capacidades: soloLeer, cartera: const []);

      expect(find.text('Nuevo cliente'), findsNothing);
      expect(find.text('Todavía no hay clientes'), findsOneWidget);
    });

    testWidgets('con `manage` el alta se ofrece en los dos sitios', (
      tester,
    ) async {
      await montar(tester, cartera: const []);

      // EL ENCABEZADO Y EL ESTADO VACÍO, que es el que se me olvidó cablear en la
      // estructura y por eso `CapacidadesDeModulo` existe.
      expect(find.text('Nuevo cliente'), findsNWidgets(2));
    });
  });

  // =========================================================================
  group('el alta', () {
    testWidgets('manda el nombre y HOY como inicio de la relación', (
      tester,
    ) async {
      final pedidas = await montar(
        tester,
        responder: (p) => p.metodo == 'POST'
            ? http.Response(
                jsonEncode(fila(id: clienteId, codigo: 'CLI-000011', nombre: 'Gimnasio Sur')),
                201,
              )
            : http.Response(jsonEncode([sportium]), 200),
      );

      await tester.tap(find.text('Nuevo cliente'));
      await tester.pumpAndSettle();

      await tester.enterText(campoDe('Nombre comercial'), 'Gimnasio Sur');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      final alta = pedidas.firstWhere((p) => p.metodo == 'POST');
      final cuerpo = jsonDecode(alta.cuerpo) as Map<String, Object?>;

      expect(cuerpo['commercialName'], 'Gimnasio Sur');

      // ⚠️ EL «HOY» SALE DEL DÍA DE NEGOCIO (D-55), no del día UTC. Comparar contra
      // `DiaDeNegocio.hoy()` y no contra una fecha escrita es lo que hace que la prueba
      // siga valiendo mañana — y lo que falla si alguien lo cambia por `DateTime.now()`
      // entre las 18:00 y las 23:59 de la Ciudad de México.
      expect(cuerpo['startedOn'], DiaDeNegocio.hoy().enTexto);

      // Y LAS OBSERVACIONES VACÍAS VAN NULAS, no como cadena vacía.
      expect(cuerpo['notes'], isNull);

      // SE DICE QUÉ SE CREÓ, CON SU FOLIO.
      expect(find.textContaining('CLI-000011'), findsOneWidget);
    });

    testWidgets('el nombre vacío se para aquí y el campo lo dice', (
      tester,
    ) async {
      final pedidas = await montar(tester);

      await tester.tap(find.text('Nuevo cliente'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('Falta el nombre comercial.'), findsOneWidget);
      expect(
        pedidas.where((p) => p.metodo == 'POST'),
        isEmpty,
        reason: 'con el nombre en blanco no hace falta ir a preguntarle al servidor',
      );
    });

    testWidgets('el logotipo se sube DESPUÉS, con PUT, al cliente creado', (
      tester,
    ) async {
      final pedidas = await montar(
        tester,
        responder: (p) => switch (p.metodo) {
          'POST' => http.Response(
            jsonEncode(fila(id: clienteId, codigo: 'CLI-000012', nombre: 'Club Norte')),
            201,
          ),
          'PUT' => http.Response(jsonEncode({'fileId': 'x'}), 200),
          _ => http.Response(jsonEncode([sportium]), 200),
        },
        selector: (_, {required donde, queReemplaza}) async =>
            LogotipoElegido(nombre: 'logo.png', bytes: Uint8List(8)),
      );

      await tester.tap(find.text('Nuevo cliente'));
      await tester.pumpAndSettle();

      await tester.enterText(campoDe('Nombre comercial'), 'Club Norte');
      await tester.tap(find.text('Elegir logotipo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      final subida = pedidas.firstWhere((p) => p.metodo == 'PUT');

      // ⚠️ `PUT` Y NO `POST`: el logotipo es un recurso SINGULAR y la ruta del servidor
      // sólo admite ese verbo. Un `POST` responde 405, un fallo que no se parece a su
      // causa — y es el error que se cometería copiando el del logotipo de la empresa.
      expect(
        subida.url.path,
        endsWith('/companies/$empresa/clients/$clienteId/logo'),
      );

      // Y EL ORDEN IMPORTA: el logotipo cuelga de un cliente que tiene que existir.
      expect(
        pedidas.indexOf(pedidas.firstWhere((p) => p.metodo == 'POST')),
        lessThan(pedidas.indexOf(subida)),
      );
    });

    testWidgets('si el logotipo falla, el cliente queda creado y se dice', (
      tester,
    ) async {
      // ⚠️ LA REGLA DEL DUEÑO, Y LA RAZÓN: callarlo dejaría a alguien creyendo que tiene
      // que volver a crear el cliente, y entonces habría dos.
      await montar(
        tester,
        responder: (p) => switch (p.metodo) {
          'POST' => http.Response(
            jsonEncode(fila(id: clienteId, codigo: 'CLI-000013', nombre: 'Club Sur')),
            201,
          ),
          'PUT' => http.Response(
            jsonEncode({
              'error': {
                'code': 'storage_capacity_exceeded',
                'message': 'No hay capacidad de almacenamiento.',
              },
            }),
            409,
          ),
          _ => http.Response(jsonEncode([sportium]), 200),
        },
        selector: (_, {required donde, queReemplaza}) async =>
            LogotipoElegido(nombre: 'logo.png', bytes: Uint8List(8)),
      );

      await tester.tap(find.text('Nuevo cliente'));
      await tester.pumpAndSettle();

      await tester.enterText(campoDe('Nombre comercial'), 'Club Sur');
      await tester.tap(find.text('Elegir logotipo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('no se pudo subir el logotipo'),
        findsOneWidget,
      );
      expect(find.textContaining('CLI-000013'), findsWidgets);
    });
  });

  // =========================================================================
  group('D-56 · el panel de alta declara lo que se perdería', () {
    testWidgets('recién abierto no hay nada que perder, con la fecha puesta', (
      tester,
    ) async {
      // ⚠️ EL CASO QUE SE ESCAPARÍA comparando contra «vacío»: el panel abre con la fecha
      // de hoy ya elegida, así que una comparación ingenua diría «sucio» sin que nadie
      // haya escrito nada, y cerrar el panel preguntaría.
      final guardia = GuardiaDeSalida();

      await montar(tester, guardia: guardia);

      await tester.tap(find.text('Nuevo cliente'));
      await tester.pumpAndSettle();

      expect(find.text('Inicio de la relación'), findsOneWidget);
      expect(
        guardia.hayCambiosSinGuardar,
        isFalse,
        reason: 'la fecha de hoy la puso el panel, no la persona',
      );
    });

    testWidgets('escribir el nombre SÍ es algo que perder, y se nombra', (
      tester,
    ) async {
      final guardia = GuardiaDeSalida();

      await montar(tester, guardia: guardia);

      await tester.tap(find.text('Nuevo cliente'));
      await tester.pumpAndSettle();

      await tester.enterText(campoDe('Nombre comercial'), 'Gimnasio Sur');
      await tester.pumpAndSettle();

      expect(guardia.hayCambiosSinGuardar, isTrue);

      // NO NOMBRA AL CLIENTE, porque todavía no hay ninguno: el nombre del campo puede
      // estar a medio escribir y preguntar por «el cliente Gimnasio Su» hablaría de algo
      // que no existe.
      expect(guardia.queSePierde, 'el cliente que estás dando de alta');
    });

    testWidgets('elegir un logotipo también es algo que perder', (
      tester,
    ) async {
      final guardia = GuardiaDeSalida();

      await montar(
        tester,
        guardia: guardia,
        selector: (_, {required donde, queReemplaza}) async =>
            LogotipoElegido(nombre: 'logo.png', bytes: Uint8List(8)),
      );

      await tester.tap(find.text('Nuevo cliente'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Elegir logotipo'));
      await tester.pumpAndSettle();

      expect(guardia.hayCambiosSinGuardar, isTrue);
    });

    testWidgets('al cerrar el panel el registro se libera', (tester) async {
      // ⚠️ SI NO SE LIBERARA, **cada navegación preguntaría** por un formulario que ya no
      // existe. Parecería un cuelgue, no un descuido.
      final guardia = GuardiaDeSalida();

      await montar(tester, guardia: guardia);

      await tester.tap(find.text('Nuevo cliente'));
      await tester.pumpAndSettle();

      await tester.enterText(campoDe('Nombre comercial'), 'Gimnasio Sur');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(guardia.hayCambiosSinGuardar, isFalse);
      expect(guardia.queSePierde, isNull);
    });
  });

  // =========================================================================
  group('el modelo', () {
    test('la fila del listado trae los conteos y la ubicación compuesta', () {
      final leida = ClienteEnLista.deJson(sportium.cast<String, dynamic>());

      expect(leida.cliente.codigo, 'CLI-000004');
      expect(leida.cliente.estado, EstatusDeCliente.activo);
      expect(leida.cliente.inicioDeLaRelacion, const DiaDeNegocio(2025, 3, 1));
      expect(leida.serviciosActivos, 2);
      expect(leida.ubicacion, 'Cuautitlán Izcalli, Estado de México');
    });

    test('un estatus desconocido deja `estado` nulo, no lo adivina', () {
      final leida = ClienteEnLista.deJson(
        fila(
          id: clienteId,
          codigo: 'CLI-000050',
          nombre: 'Marca Nueva',
          estatus: 'dormant',
        ).cast<String, dynamic>(),
      );

      expect(leida.cliente.estado, isNull);
      expect(leida.cliente.estatus, 'dormant');
    });

    test('sólo «terminado» es una relación finalizada', () {
      // Sin Descartado es un solo estatus, y quién pertenece a cada grupo lo contesta
      // el modelo y no una lista escrita en la pantalla.
      expect(EstatusDeCliente.terminado.esFinalizada, isTrue);
      expect(EstatusDeCliente.activo.esFinalizada, isFalse);
      expect(EstatusDeCliente.suspendido.esFinalizada, isFalse);
    });
  });
}
