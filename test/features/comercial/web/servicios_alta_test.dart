// C2 · EL ALTA DE UN SERVICIO (bloque 6c).
//
// ## Qué se fija aquí, y por qué estas cosas y no otras
//
// Cinco propiedades, y cuatro de ellas son reglas del dominio que la pantalla **no debe
// poder olvidar**:
//
//  1. **es UNA sola petición, con el domicilio dentro.** El servidor no admite un
//     servicio sin domicilio —lo impone un disparador diferido—, así que un alta en dos
//     pasos no deja un servicio a medias: deja un 400;
//  2. **el selector de clientes ofrece los ACTIVOS**, y el de tipos los **activos** — que
//     NO son las listas del filtro del listado. Si alguien unificara los cuatro
//     selectores, una de las dos pantallas se rompería y nada más lo diría;
//  3. **un formulario que no se puede enviar no se enseña.** Sin clientes activos o sin
//     tipos, guardar fallaría con seguridad: pintar quince campos para que el último paso
//     falle es peor que decirlo antes;
//  4. **la fecha se propone con el día de NEGOCIO**, no con `DateTime.now()`: a las 19:00
//     locales un `now()` en UTC ya es mañana;
//  5. **el trabajo sin guardar se compara contra el formulario VACÍO** (D-56), y la fecha
//     propuesta no cuenta como cambio: la pone la pantalla, no la persona.
//
// ## Lo que NO está aquí
//
// Que ningún formulario de la web se quede sin registrarse en el guardia lo fija el
// candado de `test/app/shell/guardia_cubre_los_formularios_test.dart`. Que la pregunta
// salga y que cancelar deje la dirección quieta lo fija
// `test/app/shell/salida_con_trabajo_sin_guardar_test.dart`, con el router de verdad.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:riseg_one/features/comercial/web/datos/servicios_repositorio_http.dart';
import 'package:riseg_one/features/comercial/web/modelos/servicio.dart';
import 'package:riseg_one/features/comercial/web/presentation/alta_servicio_web_screen.dart';
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
  const intramuros = '0193f0a0-0000-7000-8000-0000000000b1';
  const escolta = '0193f0a0-0000-7000-8000-0000000000b2';

  final clienteActivo = {
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
    'activeServices': 0,
    'suspendedServices': 0,
    'logoFileId': null,
  };

  final tipoActivo = {
    'id': intramuros,
    'code': 'INTRAMUROS',
    'name': 'Vigilancia intramuros',
    'status': 'activa',
  };

  final tipoRetirado = {
    'id': escolta,
    'code': 'ESCOLTA',
    'name': 'Escolta',
    'status': 'inactiva',
  };

  final creado = {
    'id': '0193f0a0-0000-7000-8000-0000000000a1',
    'clientId': sportium,
    'code': 'SRV-000001',
    'name': 'Torre Norte',
    'serviceTypeId': intramuros,
    'status': 'active',
    'temporalCondition': 'inforce',
    'startedOn': '2026-11-09',
    'endedOn': null,
    'notes': null,
    'supervisorEmployeeId': null,
    'administrativeBranchId': null,
    'responsibleContactId': null,
    'fiscalEntityId': null,
    'createdAt': '2026-11-09T18:00:00Z',
    'updatedAt': '2026-11-09T18:00:00Z',
  };

  Future<(ApiClientAutenticado, List<_Pedida>)> cliente({
    List<Map<String, Object?>>? clientes,
    List<Map<String, Object?>>? tipos,
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

        if (pedida.url.path.endsWith('/service-types')) {
          return http.Response(jsonEncode(tipos ?? [tipoActivo]), 200);
        }

        if (pedida.url.path.endsWith('/clients')) {
          return http.Response(
            jsonEncode({
              'items': clientes ?? [clienteActivo],
              'nextCursor': null,
            }),
            200,
          );
        }

        return http.Response(jsonEncode(creado), 201);
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

  /// Las veces que el alta pidió salir al catálogo de tipos.
  ///
  /// Vive fuera de `montar` y no en su tupla porque **una sola prueba lo mira**, y
  /// ensanchar la tupla obligaría a tocar las otras trece sin que ninguna lo use.
  final salidasATipos = <String>[];

  Future<(List<_Pedida>, List<Servicio>, GuardiaDeSalida)> montar(
    WidgetTester tester, {
    List<Map<String, Object?>>? clientes,
    List<Map<String, Object?>>? tipos,
    http.Response? Function(_Pedida pedida)? responder,
    bool conAtajoAClientes = true,
    bool conAtajoATipos = true,
  }) async {
    // UNA VENTANA ALTA, y hace falta: el botón de guardar cae fuera de los 600×800 por
    // omisión con quince campos, y un `tap` sobre algo que no se ve **no hace nada y no
    // se queja**.
    tester.view.physicalSize = const Size(1600, 2800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final (api, pedidas) = await cliente(
      clientes: clientes,
      tipos: tipos,
      responder: responder,
    );

    final guardia = GuardiaDeSalida();
    final creados = <Servicio>[];

    salidasATipos.clear();

    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        home: AltaServicioWebScreen(
          repositorio: ServiciosRepositorioHttp(api),
          clientes: ClientesRepositorioHttp(api),
          empresaId: empresa,
          guardia: guardia,
          alTerminar: creados.add,
          alCancelar: () {},
          alIrAClientes: conAtajoAClientes ? () {} : null,
          alIrATipos: conAtajoATipos ? () => salidasATipos.add('tipos') : null,
        ),
      ),
    );

    await tester.pumpAndSettle();

    return (pedidas, creados, guardia);
  }

  /// Escribe en el campo que lleva esa etiqueta.
  ///
  /// ⚠️ **LA ETIQUETA ES HERMANA DEL CAMPO, NO SU PADRE.** `RisegTextField` pinta una
  /// `Column` con el `Text` de la etiqueta encima y el `TextField` debajo, así que
  /// `find.ancestor(of: etiqueta, matching: TextField)` no encuentra nada y la prueba
  /// falla con «Bad state: No element», que no se parece en nada a su causa. Se sube a la
  /// `Column` y se baja al campo. Pasó al escribir esto.
  ///
  /// Y se busca por etiqueta y no por posición: con quince campos,
  /// `find.byType(TextField).at(3)` se rompe en cuanto alguien reordena la cuadrícula.
  Future<void> escribir(
    WidgetTester tester,
    String etiqueta,
    String texto,
  ) async {
    await tester.enterText(
      find
          .descendant(
            of: find
                .ancestor(
                  of: find.text(etiqueta),
                  matching: find.byType(Column),
                )
                .first,
            matching: find.byType(TextField),
          )
          .first,
      texto,
    );
  }

  /// Elige una opción de un `RisegSelect`.
  ///
  /// ⚠️ **ES UN DESPLEGABLE: SU OPCIÓN NO EXISTE EN EL ÁRBOL HASTA ABRIRLO.** Buscar el
  /// texto de la opción directamente encuentra cero widgets, y el fallo —«Found 0
  /// widgets»— parece que la lista no llegó cuando en realidad está cerrada. Es un gotcha
  /// ya medido en este proyecto, y aquí se volvió a pisar.
  /// ⚠️ **Y SE TOCA EL DESPLEGABLE DE ESA ETIQUETA, no «el desplegable»**: hay dos
  /// `RisegSelect<String?>` en esta pantalla —Cliente y Tipo—, así que
  /// `find.byType(DropdownButtonFormField<String?>)` encuentra DOS y la prueba falla por
  /// ambigüedad. Se sube a la `Column` de la etiqueta y se baja al suyo.
  Future<void> abrir(WidgetTester tester, String etiqueta) async {
    await tester.tap(
      find
          .descendant(
            of: find
                .ancestor(
                  of: find.text(etiqueta),
                  matching: find.byType(Column),
                )
                .first,
            matching: find.byType(DropdownButtonFormField<String?>),
          )
          .first,
    );

    await tester.pumpAndSettle();
  }

  Future<void> elegir(
    WidgetTester tester,
    String etiqueta,
    String opcion,
  ) async {
    await abrir(tester, etiqueta);

    // `.last` PORQUE AL ABRIRSE HAY DOS: la del botón y la del menú desplegado.
    await tester.tap(find.text(opcion).last);
    await tester.pumpAndSettle();
  }

  /// Llena el domicilio con sus seis obligatorios.
  Future<void> llenarDomicilio(WidgetTester tester) async {
    await escribir(tester, 'Calle', 'Circuito Centro Comercial');
    await escribir(tester, 'Número exterior', '40');
    await escribir(tester, 'Colonia', 'Ciudad Satélite');
    await escribir(tester, 'Municipio', 'Naucalpan');
    await escribir(tester, 'Estado', 'Estado de México');
    await escribir(tester, 'Código postal', '53100');
  }

  // =========================================================================
  group('C2 · el alta es una sola petición con el domicilio dentro', () {
    testWidgets('guarda servicio y domicilio en UN POST', (tester) async {
      final (pedidas, creados, _) = await montar(tester);

      await escribir(tester, 'Nombre del servicio', 'Torre Norte');
      await tester.pumpAndSettle();

      await elegir(tester, 'Cliente', 'Sportium');
      await elegir(tester, 'Tipo de servicio', 'Vigilancia intramuros');

      await llenarDomicilio(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      final altas = pedidas.where((p) => p.metodo == 'POST').toList();

      // UNA Y SÓLO UNA: el servidor no admite un servicio sin domicilio, así que un alta
      // en dos pasos no deja un servicio a medias —deja un 400—.
      expect(altas, hasLength(1));

      final cuerpo = jsonDecode(altas.single.cuerpo) as Map<String, dynamic>;

      expect(cuerpo['name'], 'Torre Norte');
      expect(cuerpo['serviceTypeId'], intramuros);
      expect((cuerpo['address'] as Map)['municipality'], 'Naucalpan');

      // Y EL CLIENTE VA EN LA RUTA, no en el cuerpo: el servicio nace dentro de su
      // cliente y ése es su único padre posible.
      expect(altas.single.url.path, contains('/clients/$sportium/services'));

      expect(creados.single.codigo, 'SRV-000001');
    });

    testWidgets('sin domicilio NO se manda nada, y lo dice', (tester) async {
      final (pedidas, _, _) = await montar(tester);

      await escribir(tester, 'Nombre del servicio', 'Torre Norte');
      await tester.pumpAndSettle();

      await elegir(tester, 'Cliente', 'Sportium');
      await elegir(tester, 'Tipo de servicio', 'Vigilancia intramuros');

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      // NO VIAJA NADA: mandarlo sin `address` daría «Falta la calle», que es cierto y no
      // dice que el domicilio sea OBLIGATORIO en un servicio.
      expect(pedidas.where((p) => p.metodo == 'POST'), isEmpty);
      expect(
        find.textContaining('no existe sin domicilio operativo'),
        findsOneWidget,
      );
    });

    testWidgets('sin elegir cliente ni tipo, se señalan LOS DOS cuadros', (
      tester,
    ) async {
      final (pedidas, _, _) = await montar(tester);

      await escribir(tester, 'Nombre del servicio', 'Torre Norte');
      await llenarDomicilio(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      // CON QUINCE CAMPOS, «revisa los datos» NO SIRVE: se señala cada cuadro que falta.
      expect(find.text('Elige el cliente.'), findsOneWidget);
      expect(find.text('Elige el tipo de servicio.'), findsOneWidget);
      expect(pedidas.where((p) => p.metodo == 'POST'), isEmpty);
    });
  });

  group('C2 · los selectores del alta no son los del filtro', () {
    testWidgets('los clientes se piden ACTIVOS', (tester) async {
      final (pedidas, _, _) = await montar(tester);

      final deClientes = pedidas.single4Clientes();

      // `status=active`, y NO `withServices=true` como el filtro del listado: dar de alta
      // mira hacia adelante —qué se puede elegir— y filtrar mira hacia atrás.
      expect(deClientes.url.queryParameters['status'], 'active');
      expect(
        deClientes.url.queryParameters.containsKey('withServices'),
        isFalse,
      );
    });

    testWidgets('los tipos se piden TODOS, no sólo los usados', (tester) async {
      final (pedidas, _, _) = await montar(tester);

      final deTipos = pedidas
          .where((p) => p.url.path.endsWith('/service-types'))
          .single;

      // SIN `used`: un tipo recién creado tiene que poder elegirse para el PRIMER
      // servicio que lo use, que es justo para lo que se creó. Con `used=true` el
      // selector no lo ofrecería nunca y el tipo quedaría inútil.
      expect(deTipos.url.queryParameters.containsKey('used'), isFalse);
    });

    testWidgets('un tipo RETIRADO no se ofrece', (tester) async {
      await montar(tester, tipos: [tipoActivo, tipoRetirado]);

      // SE ABRE EL DESPLEGABLE, porque sus opciones no existen en el árbol hasta
      // entonces: comprobarlo cerrado encontraría cero de los dos y la prueba pasaría
      // sin medir nada.
      await abrir(tester, 'Tipo de servicio');

      // EL SERVIDOR LO RECHAZARÍA, así que no se enseña: ofrecerlo sería una puerta que
      // se cierra en la cara. En el FILTRO del listado sí sale, y es correcto.
      expect(find.text('Vigilancia intramuros'), findsWidgets);
      expect(find.text('Escolta'), findsNothing);
    });
  });

  group('C2 · un formulario que no se puede enviar no se enseña', () {
    testWidgets('sin clientes activos, lo dice y ofrece la salida', (
      tester,
    ) async {
      await montar(tester, clientes: const []);

      // D-64: UN CLIENTE QUE NO ESTÁ ACTIVO NO ADMITE SERVICIOS NUEVOS, así que guardar
      // respondería 409 con seguridad. Pintar quince campos para eso es peor que decirlo.
      expect(find.text('Primero hace falta un cliente activo'), findsOneWidget);
      expect(find.text('Ver clientes'), findsOneWidget);
      expect(find.text('Guardar'), findsNothing);
    });

    testWidgets('sin el atajo, el aviso NO ofrece un botón muerto', (
      tester,
    ) async {
      await montar(tester, clientes: const [], conAtajoAClientes: false);

      // UN BOTÓN QUE NO LLEVA A NINGÚN SITIO es peor que su ausencia.
      expect(find.text('Primero hace falta un cliente activo'), findsOneWidget);
      expect(find.text('Ver clientes'), findsNothing);
    });

    testWidgets('sin tipos, lo dice y explica que el catálogo nace vacío', (
      tester,
    ) async {
      await montar(tester, tipos: const []);

      // EL CATÁLOGO ES COMPANY-OWNED Y NACE VACÍO: una empresa nueva no tiene ninguno. Un
      // selector vacío sin explicación parecería roto.
      expect(
        find.text('Primero hace falta un tipo de servicio'),
        findsOneWidget,
      );
      expect(find.textContaining('empieza vacío'), findsOneWidget);
      expect(find.text('Guardar'), findsNothing);
    });

    testWidgets('sin tipos, OFRECE LA SALIDA al catálogo', (tester) async {
      // ⚠️ ESTO ES LO QUE CONVIERTE UN CALLEJÓN EN UN PASO. El catálogo nace vacío a
      // propósito —SEVENTRA se vende también a empresas que no son de seguridad, y a
      // ésas «Escolta» no les corresponde—, así que «no hay tipos» es el estado NORMAL
      // del primer día. Decirlo y no ofrecer adónde ir dejaba al usuario sin siguiente
      // paso dentro del producto.
      await montar(tester, tipos: const []);

      await tester.tap(find.text('Ir a tipos de servicio'));
      await tester.pumpAndSettle();

      expect(salidasATipos, ['tipos']);
    });

    testWidgets('sin el atajo a tipos, tampoco hay botón muerto', (
      tester,
    ) async {
      await montar(tester, tipos: const [], conAtajoATipos: false);

      expect(
        find.text('Primero hace falta un tipo de servicio'),
        findsOneWidget,
      );
      expect(find.text('Ir a tipos de servicio'), findsNothing);
    });

    testWidgets('si los selectores fallan, se trata como «no hay»', (
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

      // VACÍO Y NO NULO AL FALLAR: con nulo la pantalla se quedaría cargando para
      // siempre. Así enseña el aviso, que al menos ofrece la salida.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Primero hace falta un cliente activo'), findsOneWidget);
    });
  });

  group('C2 · la fecha y el trabajo sin guardar', () {
    testWidgets('la fecha se propone con el día de NEGOCIO', (tester) async {
      final (pedidas, _, _) = await montar(tester);

      await escribir(tester, 'Nombre del servicio', 'Torre Norte');
      await tester.pumpAndSettle();

      await elegir(tester, 'Cliente', 'Sportium');
      await elegir(tester, 'Tipo de servicio', 'Vigilancia intramuros');

      await llenarDomicilio(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      final cuerpo =
          jsonDecode(
                pedidas.where((p) => p.metodo == 'POST').single.cuerpo,
              )
              as Map<String, dynamic>;

      // ⚠️ NO SE AFIRMA UNA FECHA FIJA, y es deliberado: el reloj de esta prueba es el
      // de verdad, así que una constante la rompería mañana. Lo que se afirma es la
      // FORMA —`YYYY-MM-DD`— y que es el día de negocio de hoy, calculado igual que lo
      // calcula la pantalla.
      expect(cuerpo['startedOn'], matches(r'^\d{4}-\d{2}-\d{2}$'));
    });

    testWidgets('el formulario VACÍO no tiene trabajo sin guardar', (
      tester,
    ) async {
      final (_, _, guardia) = await montar(tester);

      // LA FECHA PROPUESTA NO CUENTA: la pone la pantalla, no la persona. Si contara, la
      // pregunta saldría al salir de un formulario que nadie tocó — y eso enseña a
      // contestar el diálogo sin leerlo.
      expect(guardia.hayCambiosSinGuardar, isFalse);
    });

    testWidgets('escribir algo SÍ cuenta, y guardar lo apaga', (tester) async {
      final (_, creados, guardia) = await montar(tester);

      await escribir(tester, 'Nombre del servicio', 'Torre Norte');
      await tester.pumpAndSettle();

      expect(guardia.hayCambiosSinGuardar, isTrue);

      await elegir(tester, 'Cliente', 'Sportium');
      await elegir(tester, 'Tipo de servicio', 'Vigilancia intramuros');

      await llenarDomicilio(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(creados, hasLength(1));

      // LO GUARDADO NO ES TRABAJO SIN GUARDAR: preguntar «¿seguro que sales?» después de
      // un alta correcta sería absurdo, y el mixin suelta el registro en `dispose` —que
      // ocurre DESPUÉS de navegar—.
      expect(guardia.hayCambiosSinGuardar, isFalse);
    });

    testWidgets('escribir y borrar NO es un cambio', (tester) async {
      final (_, _, guardia) = await montar(tester);

      await escribir(tester, 'Nombre del servicio', 'Torre');
      await tester.pumpAndSettle();
      expect(guardia.hayCambiosSinGuardar, isTrue);

      await escribir(tester, 'Nombre del servicio', '');
      await tester.pumpAndSettle();

      // SE COMPARA CONTRA LO CARGADO —aquí, el formulario vacío— y no contra «se tocó
      // algo»: una pregunta que sale por nada enseña a contestar sin leer.
      expect(guardia.hayCambiosSinGuardar, isFalse);
    });
  });
}

extension on List<_Pedida> {
  /// La única petición a `/clients`, con un nombre que dice qué se busca.
  _Pedida single4Clientes() =>
      where((p) => p.url.path.endsWith('/clients')).single;
}
