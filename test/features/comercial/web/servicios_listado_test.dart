// C2 · EL LISTADO DE SERVICIOS (bloque 6b).
//
// ## Qué se fija aquí, y por qué estas cosas y no otras
//
// Cinco propiedades que se rompen en silencio si nadie las mira:
//
//  1. **los filtros los aplica el SERVIDOR y cambiar uno DESCARTA el cursor.** Con
//     paginación, continuar con el cursor viejo saltaría filas sin avisar — y funcionaría
//     perfectamente con cuatro servicios;
//  2. **el buscador no pide por tecla.** Va al servidor, así que escribir «Sportium»
//     serían ocho peticiones cuyas respuestas pueden llegar desordenadas;
//  3. **los logotipos se piden SÓLO de las filas visibles**, y aquí hay algo que el
//     listado de clientes no tenía: el logotipo es **del cliente**, así que cuatro
//     servicios de Sportium comparten archivo y se piden **una sola vez**. Esa es la
//     propiedad que más fácil se pierde al refactorizar;
//  4. **una página que falla NO borra lo que había.** Con filas pintadas, un fallo se
//     avisa debajo y el cursor se conserva;
//  5. **los dos selectores salen de listas ACOTADAS**: clientes con servicios y tipos
//     usados. Un selector que ofrece la cartera entera no acota nada.
//
// ## Lo que NO está aquí
//
// El alta y el expediente, que son 6c y 6d. Esta pantalla recibe `alDarDeAlta` y
// `alAbrirExpediente` como funciones: lo que se comprueba es **que las llame**, no a dónde
// llevan — eso lo decide el portón.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/app/shell/apartados_web.dart' show CapacidadesDeModulo;
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/api/api_client_autenticado.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/auth_api.dart';
import 'package:riseg_one/core/auth/gestor_de_sesion.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/fechas/dia_de_negocio.dart';
import 'package:riseg_one/core/logging/app_logger.dart';
import 'package:riseg_one/features/comercial/web/datos/clientes_repositorio_http.dart';
import 'package:riseg_one/features/comercial/web/datos/servicios_repositorio_http.dart';
import 'package:riseg_one/features/comercial/web/presentation/insignia_temporal.dart';
import 'package:riseg_one/features/comercial/web/presentation/servicios_web_screen.dart';
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
}

void main() {
  final config = ApiConfig.resolve(
    raw: 'http://localhost:5199',
  ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

  final t0 = DateTime.utc(2026, 11, 9, 12);

  const empresa = '0193f0a0-0000-7000-8000-000000000001';
  const sportium = '0193f0a0-0000-7000-8000-0000000000c1';
  const deacero = '0193f0a0-0000-7000-8000-0000000000c2';
  const intramuros = '0193f0a0-0000-7000-8000-0000000000b1';
  const logoDeSportium = '0193f0a0-0000-7000-8000-0000000000f1';

  Map<String, Object?> fila({
    required String id,
    required String codigo,
    required String nombre,
    String clienteId = sportium,
    String cliente = 'Sportium',
    String? logotipo = logoDeSportium,
    String estatus = 'active',
    String condicion = 'inforce',
    String? termino,
    String? ubicacion = 'Naucalpan, Estado de México',
  }) => {
    'id': id,
    'clientId': clienteId,
    'code': codigo,
    'name': nombre,
    'serviceTypeId': intramuros,
    'status': estatus,
    'temporalCondition': condicion,
    'startedOn': '2024-03-01',
    'endedOn': termino,
    'clientCommercialName': cliente,
    'clientHasLogo': logotipo != null,
    'clientLogoFileId': logotipo,
    'location': ubicacion,
  };

  Map<String, Object?> sobre(
    List<Map<String, Object?>> items, {
    String? cursorSiguiente,
  }) => {'items': items, 'nextCursor': cursorSiguiente};

  final satelite = fila(
    id: '0193f0a0-0000-7000-8000-0000000000a1',
    codigo: 'SRV-000001',
    nombre: 'Sportium Satélite',
  );

  final interlomas = fila(
    id: '0193f0a0-0000-7000-8000-0000000000a2',
    codigo: 'SRV-000002',
    nombre: 'Sportium Interlomas',
  );

  final patio = fila(
    id: '0193f0a0-0000-7000-8000-0000000000a3',
    codigo: 'SRV-000003',
    nombre: 'Patio Toluca',
    clienteId: deacero,
    cliente: 'Deacero',
    logotipo: null,
    ubicacion: null,
  );

  /// **El día que estas pruebas creen que es hoy.**
  ///
  /// ⚠️ **FIJO, Y NO `DiaDeNegocio.hoy()`.** La insignia «Termina el…» depende de cuántos
  /// días faltan, así que con el reloj de verdad una prueba que fija un término a
  /// cincuenta días **se rompería sola** el día que la suite se corriera cincuenta días
  /// después. Por eso la pantalla recibe `hoy` por el constructor.
  const hoy = DiaDeNegocio(2026, 11, 11);

  final porTerminar = fila(
    id: '0193f0a0-0000-7000-8000-0000000000a5',
    codigo: 'SRV-000012',
    nombre: 'Plaza Satélite',
    // DENTRO DE LOS TREINTA DÍAS: 19 desde el 11 de noviembre.
    termino: '2026-11-30',
  );

  final terminado = fila(
    id: '0193f0a0-0000-7000-8000-0000000000a4',
    codigo: 'SRV-000009',
    nombre: 'Bodega Vallejo',
    estatus: 'terminated',
    // ⚠️ `inforce` SOBRE UN TERMINADO, y no es un dato raro: terminar un servicio hoy no
    // mueve su fecha de término programada, así que el servidor manda las dos cosas. Es
    // la contradicción que el dueño leyó en pantalla el 11 de noviembre de 2026.
    termino: '2026-12-31',
  );

  /// Los clientes que ya tienen servicios, para el selector del filtro.
  final clientesConServicios = [
    {
      'id': sportium,
      'code': 'CLI-000004',
      'commercialName': 'Sportium',
      'status': 'active',
      'startedOn': '2023-01-01',
      'notes': null,
      // D-58 · distinto de `startedOn`: cuándo se capturó, no cuándo empezó.
      'createdAt': '2026-09-15T10:00:00Z',
      'updatedAt': '2026-10-20T18:00:00Z',
      'location': 'Naucalpan, Estado de México',
      'activeServices': 2,
      'suspendedServices': 0,
      'logoFileId': logoDeSportium,
    },
  ];

  /// Los tipos usados, para el selector del filtro.
  final tiposUsados = [
    {
      'id': intramuros,
      'code': 'INTRAMUROS',
      'name': 'Vigilancia intramuros',
      'status': 'activa',
    },
  ];

  /// El transporte, con la bitácora y una respuesta por ruta.
  ///
  /// ⚠️ **Cada ruta se responde por separado a propósito.** Esta pantalla hace TRES
  /// peticiones al abrirse —el listado y los dos selectores— y un `responder` único
  /// obligaría a cada prueba a distinguirlas a mano.
  Future<(ApiClientAutenticado, List<_Pedida>)> cliente({
    List<Map<String, Object?>>? servicios,
    String? cursorSiguiente,
    // DEVUELVE NULO PARA «SIGUE TÚ», que es lo que permite que una prueba atienda SÓLO
    // la ruta que le importa y deje las otras tres con su respuesta de siempre.
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

        final propia = responder?.call(pedida);
        if (propia != null) return propia;

        if (pedida.url.path.endsWith('/logo/content')) {
          return http.Response.bytes(Uint8List(16), 200);
        }

        if (pedida.url.path.endsWith('/service-types')) {
          return http.Response(jsonEncode(tiposUsados), 200);
        }

        if (pedida.url.path.endsWith('/clients')) {
          return http.Response(jsonEncode(sobre(clientesConServicios)), 200);
        }

        return http.Response(
          jsonEncode(
            sobre(
              servicios ??
                  [satelite, interlomas, patio, porTerminar, terminado],
              cursorSiguiente: cursorSiguiente,
            ),
          ),
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

  /// Las veces que el listado pidió abrir el catálogo de tipos.
  ///
  /// Vive fuera de `montar` y no en su tupla porque **una sola prueba lo mira**, y
  /// ensanchar la tupla obligaría a tocar las veintitantas que no lo usan.
  final tiposPedidos = <String>[];

  Future<(List<_Pedida>, List<String>, List<String>)> montar(
    WidgetTester tester, {
    CapacidadesDeModulo capacidades = todo,
    List<Map<String, Object?>>? servicios,
    String? cursorSiguiente,
    http.Response? Function(_Pedida pedida)? responder,
    Size? ventana,
  }) async {
    // UNA VENTANA CORTA SE PIDE A PROPÓSITO, y sólo la pide la prueba de visibilidad: con
    // la ventana alta **todas** las filas están a la vista, así que no podría distinguir
    // «pide sólo las visibles» de «pide todas».
    tester.view.physicalSize = ventana ?? const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final (api, pedidas) = await cliente(
      servicios: servicios,
      cursorSiguiente: cursorSiguiente,
      responder: responder,
    );

    final abiertos = <String>[];
    final altas = <String>[];

    tiposPedidos.clear();

    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        home: ServiciosWebScreen(
          repositorio: ServiciosRepositorioHttp(api),
          clientes: ClientesRepositorioHttp(api),
          empresaId: empresa,
          capacidades: capacidades,
          alAbrirExpediente: abiertos.add,
          alDarDeAlta: () => altas.add('nuevo'),
          alAbrirTipos: () => tiposPedidos.add('tipos'),
          hoy: () => hoy,
        ),
      ),
    );

    await tester.pumpAndSettle();

    return (pedidas, abiertos, altas);
  }

  /// Las peticiones al listado, que son las únicas con las que se razona aquí.
  List<_Pedida> listados(List<_Pedida> pedidas) => pedidas
      .where((p) => p.metodo == 'GET' && p.url.path.endsWith('/services'))
      .toList();

  /// Las peticiones de BYTES de logotipo, que son las que CP-20 acota.
  List<_Pedida> logotipos(List<_Pedida> pedidas) => pedidas
      .where((p) => p.metodo == 'GET' && p.url.path.endsWith('/logo/content'))
      .toList();

  // =========================================================================
  group('C2 · el catálogo de tipos se abre desde aquí', () {
    testWidgets('el botón está y llama a quien sabe navegar', (tester) async {
      final (_, _, _) = await montar(tester);

      // NO ES UNA PESTAÑA, y es una decisión: los tipos son el catálogo que ordena los
      // servicios y no merecen el mismo peso en la navegación que la cosa que ordenan.
      await tester.tap(find.text('Tipos de servicio'));
      await tester.pumpAndSettle();

      expect(tiposPedidos, ['tipos']);
    });

    testWidgets('quien SÓLO LEE también puede consultarlo', (tester) async {
      // ⚠️ NO ES UNA INCONSISTENCIA CON «Nuevo servicio», que sí desaparece: consultar
      // los tipos es `clients_services.read`, el mismo permiso con el que se está viendo
      // esta lista. La pantalla de tipos esconde sus propios botones de escritura.
      await montar(tester, capacidades: soloLeer);

      expect(find.text('Nuevo servicio'), findsNothing);
      expect(find.text('Tipos de servicio'), findsOneWidget);
    });
  });

  group('C2 · la fila trae el cliente y su ubicación', () {
    testWidgets('el nombre del servicio, el del cliente y el folio', (
      tester,
    ) async {
      await montar(tester);

      expect(find.text('Sportium Satélite'), findsOneWidget);

      // EL CLIENTE Y EL FOLIO EN UNA LÍNEA, con `·` y no con una coma: los nombres
      // comerciales llevan comas —«Ríos, S.A. de C.V.»— y dos comas seguidas no se leen.
      expect(find.text('Sportium · SRV-000001'), findsOneWidget);
      expect(find.text('Deacero · SRV-000003'), findsOneWidget);
    });

    testWidgets('la ubicación sin domicilio dice «No registrada»', (
      tester,
    ) async {
      await montar(tester);

      expect(find.text('Naucalpan, Estado de México'), findsWidgets);

      // DESDE LA 0059 ESTO NO DEBERÍA PASAR —ningún servicio existe sin domicilio—, así
      // que es una red y no un estado esperado. Que exista la red se prueba igual.
      expect(find.text('No registrada'), findsOneWidget);
    });

    testWidgets('el estatus y, debajo, el eje temporal', (tester) async {
      await montar(tester);

      // LOS CUATRO VIGENTES ENSEÑAN LOS DOS EJES: qué se decidió y dónde cae hoy. El
      // quinto —el terminado— no se pinta con el chip en «Vigentes», y se mira abajo.
      expect(find.text('Activo'), findsNWidgets(4));

      // TRES DICEN «VIGENTE» Y EL CUARTO NO: el que termina en diecinueve días dice
      // cuándo termina, porque **lo urgente desplaza lo cierto**.
      expect(find.text('Vigente'), findsNWidgets(3));
      expect(find.text('Termina el 30/nov/2026'), findsOneWidget);
    });

    testWidgets('«Termina el…» sólo dentro de los treinta días', (tester) async {
      // EL CONTRAPUNTO, Y NO SOBRA: si la insignia saliera siempre que hay término, lo
      // diría de un servicio que termina en dos años y dejaría de significar «atiéndelo».
      await montar(
        tester,
        servicios: [
          fila(
            id: '0193f0a0-0000-7000-8000-0000000000a6',
            codigo: 'SRV-000013',
            nombre: 'Lejano',
            // 31 DÍAS: uno más que el umbral, a propósito. Un límite que no se mide por
            // los dos lados no está medido.
            termino: '2026-12-12',
          ),
          fila(
            id: '0193f0a0-0000-7000-8000-0000000000a7',
            codigo: 'SRV-000014',
            nombre: 'Justo en el límite',
            // 30 DÍAS EXACTOS: el umbral INCLUYE su día.
            termino: '2026-12-11',
          ),
        ],
      );

      expect(find.text('Termina el 12/dic/2026'), findsNothing);
      expect(find.text('Termina el 11/dic/2026'), findsOneWidget);
      expect(find.text('Vigente'), findsOneWidget);
    });

    testWidgets('un TERMINADO no dice «Vigente»: dice cuándo terminó', (
      tester,
    ) async {
      // 🚫 **LA CONTRADICCIÓN QUE EL DUEÑO LEYÓ EN PANTALLA**, en el listado: el servidor
      // manda `terminated` **y** `inforce`, porque terminar un servicio no mueve su fecha
      // de término programada. En un terminado el eje temporal dice cuándo terminó.
      //
      // Sale del mismo sitio que el expediente —`insignia_temporal.dart`—, y es lo que
      // impide que las dos pantallas se separen.
      await montar(tester);

      await tester.tap(find.text('Finalizados'));
      await tester.pumpAndSettle();

      expect(find.text('Terminado'), findsOneWidget);
      expect(find.text('Terminó el 31/dic/2026'), findsOneWidget);
      expect(find.text('Vigente'), findsNothing);
    });

    testWidgets('las columnas de C5 NO existen, y no salen en cero', (
      tester,
    ) async {
      await montar(tester);

      // NI LA COLUMNA NI UN CERO: un cero diría que el servicio no tiene gente, que es
      // una respuesta falsa y plausible. El escritorio las tiene; aquí llegan con C5.
      expect(find.text('Personal'), findsNothing);
      expect(find.text('Esquema/Turno'), findsNothing);
      expect(find.text('Turno'), findsNothing);
    });
  });

  group('C2 · los logotipos del listado de servicios', () {
    testWidgets(
      'DOS servicios del mismo cliente comparten UNA sola petición',
      (tester) async {
        final (pedidas, _, _) = await montar(
          tester,
          servicios: [satelite, interlomas],
        );

        // ES LA PROPIEDAD QUE ESTE LISTADO GANA SOBRE EL DE CLIENTES: el logotipo es del
        // CLIENTE, así que dos servicios de Sportium comparten `fileId` y la caché —que
        // va por ARCHIVO y guarda el `Future` en vuelo— pide los bytes una vez. Con una
        // caché por servicio serían dos, y con cuatro sedes, cuatro.
        expect(
          logotipos(pedidas),
          hasLength(1),
          reason: 'dos filas del mismo cliente deben compartir la petición',
        );
      },
    );

    testWidgets('un cliente SIN logotipo no genera ninguna petición', (
      tester,
    ) async {
      final (pedidas, _, _) = await montar(tester, servicios: [patio]);

      // NO SE PIDE LO QUE NO EXISTE: la fila pinta las iniciales del cliente y no hay
      // viaje. Es la mitad de CP-20 que se olvida al refactorizar.
      expect(logotipos(pedidas), isEmpty);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('sólo se piden los de las filas VISIBLES', (tester) async {
      // Cuarenta servicios de clientes DISTINTOS: con el mismo cliente la caché los
      // colapsaría a uno y la prueba no mediría la visibilidad.
      final muchos = [
        for (var i = 0; i < 40; i++)
          fila(
            id: '0193f0a0-0000-7000-8000-00000000${(100 + i)}',
            codigo: 'SRV-${(i + 1).toString().padLeft(6, '0')}',
            nombre: 'Servicio $i',
            clienteId: '0193f0a0-0000-7000-8000-00000000${(200 + i)}',
            cliente: 'Cliente $i',
            logotipo: '0193f0a0-0000-7000-8000-00000000${(300 + i)}',
          ),
      ];

      final (pedidas, _, _) = await montar(
        tester,
        servicios: muchos,
        ventana: const Size(1200, 700),
      );

      // LA COTA ES LA MITAD DE LA PÁGINA A PROPÓSITO: «menos de cuarenta» se cumpliría
      // pidiendo treinta y nueve y no mediría nada.
      expect(
        logotipos(pedidas).length,
        lessThan(20),
        reason: 'pidió ${logotipos(pedidas).length} de 40',
      );

      expect(logotipos(pedidas), isNotEmpty);
    });

    testWidgets('si los bytes fallan, la fila sigue enseñando iniciales', (
      tester,
    ) async {
      await montar(
        tester,
        servicios: [satelite],
        responder: (p) => p.url.path.endsWith('/logo/content')
            ? http.Response('nope', 500)
            : null,
      );

      // UN HUECO ROTO SERÍA PEOR QUE EL RESPALDO QUE YA EXISTE, y la caché guarda el
      // fallo para no reintentar en bucle.
      expect(find.text('Sportium Satélite'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });

  group('C2 · los filtros y la paginación', () {
    testWidgets('un ARREGLO PELADO se rechaza: el contrato es el sobre', (
      tester,
    ) async {
      await montar(
        tester,
        responder: (p) => p.url.path.endsWith('/services')
            ? http.Response(jsonEncode([satelite]), 200)
            : null,
      );

      expect(find.text('No se pudieron cargar los servicios'), findsOneWidget);
    });

    testWidgets('sin cursor NO se ofrece «Cargar más»', (tester) async {
      await montar(tester);

      expect(find.text('Cargar más'), findsNothing);
    });

    testWidgets('«Cargar más» pide con el cursor y AÑADE al final', (
      tester,
    ) async {
      final (pedidas, _, _) = await montar(
        tester,
        servicios: [satelite],
        cursorSiguiente: 'c_2',
      );

      await tester.tap(find.text('Cargar más'));
      await tester.pumpAndSettle();

      final conCursor = listados(
        pedidas,
      ).where((p) => p.url.queryParameters['cursor'] == 'c_2');

      expect(conCursor, hasLength(1));
    });

    testWidgets('cambiar un filtro DESCARTA el cursor', (tester) async {
      final (pedidas, _, _) = await montar(
        tester,
        servicios: [satelite],
        cursorSiguiente: 'c_2',
      );

      await tester.tap(find.text('Cargar más'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Finalizados'));
      await tester.pumpAndSettle();

      // ⚠️ LA PETICIÓN DEL CHIP NO LLEVA CURSOR. Un cursor es la posición dentro de *ese*
      // resultado: continuar con el de la búsqueda anterior saltaría filas sin avisar, y
      // con cuatro servicios nadie lo notaría.
      final ultima = listados(pedidas).last;

      expect(ultima.url.queryParameters.containsKey('cursor'), isFalse);
      expect(ultima.url.queryParameters['status'], 'terminated');
    });

    testWidgets('una página que falla NO borra lo que había', (tester) async {
      var vueltas = 0;

      final (pedidas, _, _) = await montar(
        tester,
        servicios: [satelite],
        cursorSiguiente: 'c_2',
        responder: (p) {
          if (!p.url.path.endsWith('/services')) return null;

          // La primera va bien; la segunda —la de «Cargar más»— falla.
          if (vueltas++ == 0) return null;

          return http.Response('{"code":"error_interno"}', 500);
        },
      );

      await tester.tap(find.text('Cargar más'));
      await tester.pumpAndSettle();

      // LA FILA SIGUE AHÍ Y EL AVISO VA DEBAJO: si se borrara, la persona creería que la
      // lista se acaba donde se acabó la última página buena.
      expect(find.text('Sportium Satélite'), findsOneWidget);
      expect(
        find.textContaining('No se pudieron cargar más servicios'),
        findsOneWidget,
      );

      // Y EL CURSOR SE CONSERVA, así que se puede volver a intentar.
      expect(find.text('Cargar más'), findsOneWidget);
      expect(listados(pedidas).length, greaterThanOrEqualTo(2));
    });

    testWidgets('el buscador NO pide por tecla', (tester) async {
      final (pedidas, _, _) = await montar(tester);

      final antes = listados(pedidas).length;

      await tester.enterText(find.byType(TextField).first, 'sportium');
      await tester.pump(const Duration(milliseconds: 100));

      // TODAVÍA NADA: con una petición por tecla, «sportium» serían ocho, y sus
      // respuestas pueden llegar desordenadas —la de «spo» después de la de «sportium»
      // dejaría la lista enseñando una búsqueda que ya nadie está haciendo—.
      expect(listados(pedidas).length, antes);

      // ⚠️ SE AVANZA EL RELOJ A MANO Y DESPUÉS SE DEJA ASENTAR. `pumpAndSettle` por sí
      // solo **no basta**: bombea hasta que no queden fotogramas pendientes, y un `Timer`
      // no programa fotogramas — así que volvía sin haber cumplido los 350 ms y la
      // petición no había salido. Lo descubrió este fallo.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final despues = listados(pedidas).where(
        (p) => p.url.queryParameters['query'] == 'sportium',
      );

      expect(despues, hasLength(1));
    });

    testWidgets('el chip «Por terminar» filtra EN EL SERVIDOR, con su ventana', (
      tester,
    ) async {
      // 🚫 **NO SE FILTRA EN LA PANTALLA, Y NO ES UNA PREFERENCIA.** El listado pagina por
      // cursor, así que acotarlo aquí dejaría «por terminar» reducido a *los que terminan
      // pronto de los primeros cincuenta por nombre*, escondiendo el resto sin decirlo.
      final (pedidas, _, _) = await montar(tester);

      await tester.tap(find.text('Por terminar'));
      await tester.pumpAndSettle();

      final ultima = listados(pedidas).last;

      // ⚠️ **LA VENTANA ES LA MISMA CONSTANTE QUE DECIDE LA INSIGNIA**, y eso es lo que
      // impide que el chip y la fila se contradigan: una fila sin insignia dentro del
      // grupo sería un servicio que el filtro dice que termina pronto y la fila no.
      expect(
        ultima.url.queryParameters['endingWithin'],
        '$diasParaEstarPorTerminar',
      );

      // Y NO VIAJA UN ESTATUS: el servidor ya excluye los terminados en ese filtro, y
      // mandar `status` además acotaría a uno de los dos vigentes.
      expect(ultima.url.queryParameters.containsKey('status'), isFalse);
    });

    testWidgets('el chip Finalizados filtra EN EL SERVIDOR', (tester) async {
      final (pedidas, _, _) = await montar(tester);

      await tester.tap(find.text('Finalizados'));
      await tester.pumpAndSettle();

      // EL GRUPO ES EXACTAMENTE UN ESTATUS, así que el servidor puede filtrarlo. En
      // «Vigentes» son dos y no viaja ninguno: ésa es la única exclusión de la pantalla.
      expect(listados(pedidas).last.url.queryParameters['status'], 'terminated');
    });
  });

  group('C2 · los dos selectores acotados', () {
    testWidgets('el de cliente pide los que YA TIENEN servicios', (
      tester,
    ) async {
      final (pedidas, _, _) = await montar(tester);

      final deClientes = pedidas.where(
        (p) => p.metodo == 'GET' && p.url.path.endsWith('/clients'),
      );

      // `withServices=true`, igual que el escritorio: un selector que ofrece la cartera
      // entera para acotar cuatro servicios no acota nada.
      expect(deClientes, hasLength(1));
      expect(deClientes.single.url.queryParameters['withServices'], 'true');
    });

    testWidgets('el de tipo pide los USADOS, no todos', (tester) async {
      final (pedidas, _, _) = await montar(tester);

      final deTipos = pedidas.where(
        (p) => p.metodo == 'GET' && p.url.path.endsWith('/service-types'),
      );

      // ⚠️ `used=true` Y NO LA LISTA DEL ALTA, que son los ACTIVOS: filtrar mira hacia
      // atrás —qué hay— y dar de alta mira hacia adelante —qué se puede elegir—.
      expect(deTipos, hasLength(1));
      expect(deTipos.single.url.queryParameters['used'], 'true');
    });

    testWidgets('si los selectores fallan, el listado SIGUE sirviendo', (
      tester,
    ) async {
      await montar(
        tester,
        responder: (p) =>
            p.url.path.endsWith('/clients') ||
                p.url.path.endsWith('/service-types')
            ? http.Response('{"code":"error_interno"}', 500)
            : null,
      );

      // LO QUE SE PIERDE SON DOS FILTROS, NO LA PESTAÑA: el listado se ve y se puede
      // buscar por texto. Un fallo de un selector que tumbara la pantalla sería
      // desproporcionado.
      expect(find.text('Sportium Satélite'), findsOneWidget);
      expect(find.text('No se pudieron cargar los servicios'), findsNothing);
    });
  });

  group('C2 · permisos y vacíos', () {
    testWidgets('sin permiso de crear NO hay botón de alta', (tester) async {
      await montar(tester, capacidades: soloLeer);

      // NO ES LO MISMO QUE UN BOTÓN APAGADO: lo que esta persona no puede hacer no se le
      // enseña.
      expect(find.text('Nuevo servicio'), findsNothing);
    });

    testWidgets('con permiso, el botón llama al alta', (tester) async {
      final (_, _, altas) = await montar(tester);

      await tester.tap(find.text('Nuevo servicio'));
      await tester.pumpAndSettle();

      // LA PANTALLA PIDE, NO NAVEGA: quien conoce la ruta es el portón.
      expect(altas, ['nuevo']);
    });

    testWidgets('clic en la fila abre su expediente', (tester) async {
      final (_, abiertos, _) = await montar(tester, servicios: [satelite]);

      await tester.tap(find.text('Sportium Satélite'));
      await tester.pumpAndSettle();

      expect(abiertos, ['0193f0a0-0000-7000-8000-0000000000a1']);
    });

    testWidgets('el vacío de verdad EXPLICA qué es un servicio', (
      tester,
    ) async {
      await montar(tester, servicios: const []);

      // QUIEN ABRE ESTO POR PRIMERA VEZ puede no saber que un cliente con cuatro sedes
      // tiene cuatro servicios, y que cada uno lleva su propio domicilio.
      expect(find.text('Todavía no hay servicios'), findsOneWidget);
      expect(find.textContaining('cuatro sedes'), findsOneWidget);
    });

    testWidgets('el vacío por FILTRO dice otra cosa', (tester) async {
      await montar(tester, servicios: const []);

      await tester.tap(find.text('Finalizados'));
      await tester.pumpAndSettle();

      // CONFUNDIR LOS DOS HARÍA PENSAR QUE NO HAY NADA CAPTURADO: «ningún servicio
      // finalizado» es una buena noticia, no una lista que falta.
      expect(find.text('Ningún servicio finalizado'), findsOneWidget);
      expect(find.text('Todavía no hay servicios'), findsNothing);
    });

    testWidgets('un estatus desconocido se enseña TAL CUAL y cuenta como vigente', (
      tester,
    ) async {
      await montar(
        tester,
        servicios: [
          fila(
            id: '0193f0a0-0000-7000-8000-0000000000a5',
            codigo: 'SRV-000010',
            nombre: 'Fantasma',
            estatus: 'archivado',
          ),
        ],
      );

      // NI UNA EXCEPCIÓN NI UN «Activo» POR OMISIÓN: se enseña el código con tono
      // neutro. Y cuenta como vigente, porque de los dos errores posibles, una fila de
      // más en Vigentes se ve y se corrige; esconderla en los dos grupos la haría
      // desaparecer de la pantalla.
      expect(find.text('Fantasma'), findsOneWidget);
      expect(find.text('archivado'), findsOneWidget);
    });
  });
}
