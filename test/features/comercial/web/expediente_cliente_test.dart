// C1 · EL EXPEDIENTE DE UN CLIENTE: la ficha, los indicadores, los datos generales y el
// domicilio de referencia.
//
// ## Lo que se fija aquí, y por qué
//
// Cuatro cosas que, si se rompen, no fallan:
//
//  1. **la razón social sólo con UNA entidad fiscal activa.** Con 0 o 2+ sería ambiguo,
//     y enseñar «la primera» sería inventar con qué razón social se factura;
//  2. **sólo viaja lo que cambió**, porque el servidor rechaza un `PATCH` que no cambia
//     nada: mandar el cuerpo completo haría que pulsar «Guardar» sin tocar nada
//     respondiera un 400;
//  3. **el motivo se pide ANTES de mandar nada**, y cancelarlo no guarda ni pierde;
//  4. **si el cliente se guarda y el domicilio falla, se dice qué quedó guardado.** Son
//     dos rutas del servidor y no hay una que escriba las dos en una transacción, así
//     que callarlo dejaría a alguien reescribiendo el nombre que ya se guardó.
//
// Y una que es del contrato: **el domicilio no se puede quitar desde aquí**. El servidor
// no tiene `DELETE` y su `PUT` exige los seis obligatorios.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/app/shell/apartados_web.dart' show CapacidadesDeModulo;
import 'package:riseg_one/app/shell/router_web.dart' show seguroDeSalir;
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/api/api_client_autenticado.dart';
import 'package:riseg_one/core/archivos/elegir_logotipo.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/auth_api.dart';
import 'package:riseg_one/core/auth/gestor_de_sesion.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/logging/app_logger.dart';
import 'package:riseg_one/core/trabajo_sin_guardar/guardia_de_salida.dart';
import 'package:riseg_one/core/fechas/dia_de_negocio.dart';
import 'package:riseg_one/features/comercial/web/datos/clientes_repositorio_http.dart';
import 'package:riseg_one/features/comercial/web/datos/servicios_repositorio_http.dart';
import 'package:riseg_one/features/comercial/web/modelos/cliente.dart';
import 'package:riseg_one/features/comercial/web/presentation/expediente_cliente_web_screen.dart';
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

  Map<String, Object?> get json =>
      jsonDecode(cuerpo) as Map<String, Object?>;
}

void main() {
  final config = ApiConfig.resolve(
    raw: 'http://localhost:5199',
  ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

  final t0 = DateTime.utc(2026, 10, 26, 12);

  const empresa = '0193f0a0-0000-7000-8000-000000000001';
  const clienteId = '0193f0a0-0000-7000-8000-0000000000c1';

  /// Otro cliente, **para poder salir de verdad de la ficha** en la prueba de guardar: sin
  /// una segunda dirección que exista en este router, «irse» no se puede medir.
  const otroCliente = '0193f0a0-0000-7000-8000-0000000000c9';

  /// El día que estas pruebas creen que es hoy, **fijo**: la insignia «Termina el…» de los
  /// servicios del cliente depende de cuántos días faltan.
  const hoy = DiaDeNegocio(2026, 11, 12);

  /// Una fila del listado de servicios, como la manda el servidor.
  Map<String, Object?> unServicio({
    required String codigo,
    required String nombre,
    String id = '0193f0a0-0000-7000-8000-0000000000a1',
    String estatus = 'active',
    String? termino,
  }) => {
    'id': id,
    'clientId': clienteId,
    'code': codigo,
    'name': nombre,
    'serviceTypeId': '0193f0a0-0000-7000-8000-0000000000b1',
    'status': estatus,
    'temporalCondition': 'inforce',
    'startedOn': '2024-03-01',
    'endedOn': termino,
    'clientCommercialName': 'Sportium',
    'clientHasLogo': false,
    'clientLogoFileId': null,
    'location': 'Naucalpan, Estado de México',
  };

  /// Un cuerpo de error **con la forma que el servidor manda de verdad**.
  ///
  /// ⚠️ **ES PLANA Y NO `{"error": {...}}`**: el servidor serializa
  /// `ErrorResponse(code, message)` al nivel superior, y `ApiErrorParser` los lee de ahí.
  /// Con el sobre `error` el parser no los encuentra y compone un mensaje de diagnóstico,
  /// así que **una prueba de un camino de error probaría menos de lo que dice sin fallar**.
  String elError(String codigo, String mensaje) =>
      jsonEncode({'code': codigo, 'message': mensaje});

  Map<String, Object?> elCliente({
    String nombre = 'Sportium',
    String estatus = 'active',
    String? observaciones = 'Cliente desde 2025.',
  }) => {
    'id': clienteId,
    'code': 'CLI-000004',
    'commercialName': nombre,
    'status': estatus,
    'startedOn': '2025-03-01',
    'notes': observaciones,
    // ⚠️ **D-58 · `createdAt` ES DISTINTO DE `startedOn` A PROPÓSITO**, y por eso el año
    // no coincide: uno dice cuándo empezó el negocio y el otro cuándo se capturó la
    // fila. Si alguien «simplificara» poniéndolos iguales, la prueba que mide la
    // diferencia dejaría de medir nada.
    'createdAt': '2026-09-15T10:00:00Z',
    'updatedAt': '2026-10-20T18:00:00Z',
  };

  Map<String, Object?> elDomicilio({String colonia = 'Juárez'}) => {
    'id': '0193f0a0-0000-7000-8000-0000000000d1',
    'street': 'Av. Reforma',
    'exteriorNumber': '222',
    'interiorNumber': null,
    'neighborhood': colonia,
    'municipality': 'Cuauhtémoc',
    'city': null,
    'state': 'Ciudad de México',
    'postalCode': '06600',
    'country': 'México',
    'landmarks': null,
    'updatedAt': '2026-10-20T18:00:00Z',
  };

  Map<String, Object?> laEntidad({
    required String id,
    required String razon,
    String? rfc = 'SPO210101AAA',
    String estatus = 'active',
  }) => {
    'id': id,
    'clientId': clienteId,
    'legalName': razon,
    'taxId': rfc,
    'fiscalRegimeCode': '601',
    'status': estatus,
    'notes': null,
    'updatedAt': '2026-10-20T18:00:00Z',
  };

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

  /// El cliente HTTP con la bitácora. **Responde por RUTA**, que es lo que hace legible
  /// una pantalla que pide cinco cosas a la vez.
  Future<(ApiClientAutenticado, List<_Pedida>)> cliente({
    Map<String, Object?>? datos,
    Map<String, Object?>? domicilio,
    List<Map<String, Object?>> entidades = const [],
    List<Map<String, Object?>> servicios = const [],
    List<Monto> importes = const [],
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

        final ruta = p.url.path;

        if (ruta.endsWith('/indicators')) {
          return http.Response(
            jsonEncode({
              'activeServices': 3,
              'suspendedServices': 1,
              'monthlyAmount': [
                for (final m in importes)
                  {'currency': m.moneda, 'totalMinor': m.menores},
              ],
            }),
            200,
          );
        }

        if (ruta.endsWith('/fiscal-entities')) {
          return http.Response(jsonEncode(entidades), 200);
        }

        // LOS SERVICIOS DE ESTE CLIENTE, para la tarjeta de su expediente.
        if (ruta.endsWith('/services')) {
          return http.Response(
            jsonEncode({'items': servicios, 'nextCursor': null}),
            200,
          );
        }

        if (ruta.endsWith('/address')) {
          return domicilio == null
              ? http.Response(
                  elError(
                    'not_found',
                    'Ese cliente no tiene domicilio de referencia.',
                  ),
                  404,
                )
              : http.Response(jsonEncode(domicilio), 200);
        }

        if (ruta.endsWith('/logo/content')) {
          return http.Response(elError('logo_missing', 'Sin logotipo.'), 404);
        }

        return http.Response(jsonEncode(datos ?? elCliente()), 200);
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

  void ventanaAlta(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 2600);
    tester.view.devicePixelRatio = 1;

    addTearDown(tester.view.reset);
  }

  /// Monta el expediente **dentro de un router de verdad**, con las dos direcciones que
  /// la pantalla usa: la consulta y la edición.
  Future<
    ({
      List<_Pedida> pedidas,
      GoRouter router,
      List<String> nombres,
      List<String> abiertos,
    })
  >
  montar(
    WidgetTester tester, {
    /// Si se le da el repositorio de Servicios, la ficha enseña **los servicios del
    /// cliente**. Nulo en casi todas las pruebas: lo que miden es otra cosa, y una
    /// tarjeta que no puede cargar nada **no se pinta** —si se pintara, su indicador no
    /// se apagaría nunca y `pumpAndSettle` no volvería—.
    bool conSusServicios = false,
    List<Map<String, Object?>> servicios = const [],
    GuardiaDeSalida? guardia,
    CapacidadesDeModulo capacidades = todo,
    Map<String, Object?>? datos,
    Map<String, Object?>? domicilio,
    List<Map<String, Object?>> entidades = const [],
    List<Monto> importes = const [],
    http.Response? Function(_Pedida pedida)? responder,
    SelectorDeLogotipo? selector,
    bool editando = false,
  }) async {
    ventanaAlta(tester);

    final (api, pedidas) = await cliente(
      datos: datos,
      domicilio: domicilio,
      entidades: entidades,
      servicios: servicios,
      importes: importes,
      responder: responder,
    );

    final nombres = <String>[];

    /// Lo que se abrió desde la tarjeta de servicios: un id, o `'todos'`.
    final abiertos = <String>[];

    // ⚠️ **EL GUARDIA ES UNO SOLO PARA LAS DOS RUTAS**, como en el producto: la pantalla
    // se registra en él y el `onExit` de la ruta le pregunta. Antes se creaba uno nuevo
    // por `builder` cuando el llamador no pasaba ninguno, así que las dos pantallas
    // hablaban con guardias distintos y nada podía fallar.
    final elGuardia = guardia ?? GuardiaDeSalida();

    final router = GoRouter(
      initialLocation: editando
          ? '/comercial/clientes/$clienteId/editar'
          : '/comercial/clientes/$clienteId',
      routes: [
        GoRoute(
          path: '/comercial/clientes/:id',
          // 🚫 **CON `onExit`, COMO EL ROUTER DE VERDAD**, y ésta es la mitad que
          // faltaba: sin él, esta prueba montaba un router que **no pregunta nunca**, así
          // que «guardar y volver» nunca se medía contra la guardia. El dueño lo encontró
          // en pantalla el 12 de noviembre de 2026: guardaba, se quedaba en `/editar` y
          // al salir le preguntaba si quería tirar lo que ya estaba guardado.
          onExit: (contexto, _) => seguroDeSalir(contexto, elGuardia),
          // LAS DOS DIRECCIONES, con la misma pantalla y `editando` distinto: es la
          // forma exacta que usa el portón, y montar sólo una mediría la mitad.
          builder: (contexto, estado) => ExpedienteClienteWebScreen(
            repositorio: ClientesRepositorioHttp(api),
            empresaId: empresa,
            clienteId: estado.pathParameters['id']!,
            capacidades: capacidades,
            guardia: elGuardia,
            editando: false,
            alIrADentro: (aDonde) => contexto.go(
              '/comercial/clientes/${estado.pathParameters['id']}'
              '${aDonde == null ? '' : '/$aDonde'}',
            ),
            alVolver: () {},
            alConocerElNombre: (_, nombre) => nombres.add(nombre),
            elegirUnLogotipo: selector ?? elegirLogotipo,
            repositorioDeServicios: conSusServicios
                ? ServiciosRepositorioHttp(api)
                : null,
            alAbrirServicio: abiertos.add,
            alVerSusServicios: () => abiertos.add('todos'),
            hoy: () => hoy,
          ),
          routes: [
            GoRoute(
              path: 'editar',
              // ⚠️ **TAMBIÉN AQUÍ, y es lo que hace fiel a esta prueba:** en el router de
              // verdad las rutas son **planas** —`/` y el comodín—, así que pasar de
              // `…/editar` a `…/<id>` es **salir de una ruta** y dispara su `onExit`. Con
              // el `onExit` sólo en la ruta padre, esa salida no pasaba por nadie y la
              // prueba no podía ver lo que el dueño vio.
              onExit: (contexto, _) => seguroDeSalir(contexto, elGuardia),
              builder: (contexto, estado) => ExpedienteClienteWebScreen(
                repositorio: ClientesRepositorioHttp(api),
                empresaId: empresa,
                clienteId: estado.pathParameters['id']!,
                capacidades: capacidades,
                guardia: elGuardia,
                editando: true,
                alIrADentro: (aDonde) => contexto.go(
                  '/comercial/clientes/${estado.pathParameters['id']}'
                  '${aDonde == null ? '' : '/$aDonde'}',
                ),
                alVolver: () {},
                alConocerElNombre: (_, nombre) => nombres.add(nombre),
                elegirUnLogotipo: selector ?? elegirLogotipo,
              ),
            ),
          ],
        ),
      ],
    );

    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: MarcaSeventra.tema(), routerConfig: router),
    );
    await tester.pumpAndSettle();

    return (
      pedidas: pedidas,
      router: router,
      nombres: nombres,
      abiertos: abiertos,
    );
  }

  Finder campoDe(String etiqueta) => find
      .descendant(
        of: find
            .ancestor(of: find.text(etiqueta), matching: find.byType(Column))
            .first,
        matching: find.byType(TextField),
      )
      .first;

  /// Un texto **dentro de la ficha**, no en toda la pantalla.
  ///
  /// La razón social sale dos veces desde que la sección de entidades fiscales vive en
  /// esta pantalla: en la ficha —sólo con **una** activa, que es la regla— y en la lista
  /// —siempre—. Sin acotar, las dos pruebas de la regla medirían la lista.
  Finder enLaFicha(String texto) => find.descendant(
    of: find.byKey(claveDeLaEntidadDeLaFicha),
    matching: find.text(texto),
  );

  /// Abre una pestaña del expediente: **General · Domicilio · Contactos · Razones
  /// sociales**.
  ///
  /// ⚠️ **ES NUEVO CON EL ESTILO B, elegido por el dueño el 11 de noviembre de 2026**, y
  /// cambia cómo se escribe una prueba de esta pantalla: antes las ocho secciones estaban
  /// apiladas, así que cualquier `find` las encontraba. Ahora **lo que no está en la
  /// pestaña abierta no está en el árbol**, que es lo que el estilo compra —un asunto a la
  /// vez— y lo que obliga a decir aquí a cuál se va.
  Future<void> abrirPestana(WidgetTester tester, String cual) async {
    await tester.tap(find.text(cual));
    await tester.pumpAndSettle();
  }

  /// Escribe el motivo del diálogo y confirma.
  Future<void> darElMotivo(WidgetTester tester, String motivo) async {
    await tester.enterText(find.byType(TextField).last, motivo);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar').last);
    await tester.pumpAndSettle();
  }

  List<_Pedida> delCliente(List<_Pedida> pedidas, String metodo) => pedidas
      .where(
        (p) =>
            p.metodo == metodo &&
            p.url.path.endsWith('/clients/$clienteId'),
      )
      .toList();

  // =========================================================================
  group('la ficha', () {
    testWidgets('dice el nombre, el folio y el estatus', (tester) async {
      await montar(tester);

      // `findsWidgets` Y NO `findsOneWidget`: el nombre sale **dos veces** y es lo
      // correcto —en la cabecera, grande, y dentro del campo «Nombre comercial»—. Fijar
      // uno obligaría a esconder el dato en un sitio para que la prueba pasara.
      expect(find.text('Sportium'), findsWidgets);
      expect(find.text('CLI-000004'), findsWidgets);
      expect(find.text('Activo'), findsOneWidget);
    });

    testWidgets('D-58 · enseña el ALTA y el INICIO, y NO son la misma fecha', (
      tester,
    ) async {
      // ✅ **D-58 PARTE 1, en la pantalla.** `createdAt` llegó al contrato en el bloque 3
      // de C2 y las dos fichas lo publican. Lo que esta prueba fija es que la pantalla
      // enseñe **las dos** y que no se confundan: el cliente empezó el 1 de marzo de
      // 2025 y se capturó el 15 de septiembre de 2026.
      //
      // ⚠️ **Se afirma la DIFERENCIA y no sólo la presencia.** La única manera de que
      // nadie vuelva a usar un campo por el otro es medir que son distintos: con las dos
      // fechas iguales, esta prueba pasaría sin comprobar nada.
      await montar(tester);

      expect(find.text('Alta en el sistema'), findsOneWidget);
      expect(find.text('Inicio de la relación'), findsOneWidget);

      // ⚠️ **SE LEEN COMO TEXTO Y YA NO COMO CAMPOS**, y es el estilo B: en consulta no
      // hay un solo cuadro. La propiedad que se mide es la misma —son dos fechas
      // distintas y no se confunden—, y ahora se mide donde la persona la lee.
      expect(find.textContaining('15/sep/2026'), findsOneWidget);
      expect(find.text('1/mar/2025'), findsOneWidget);
    });

    testWidgets('🚫 enseña SUS SERVICIOS, con acceso a cada uno', (
      tester,
    ) async {
      // 🚫 **AQUÍ HABÍA UN HUECO CON JERGA Y SIN NÚMERO**: «verlos aquí dentro llega con
      // la cobertura del módulo». El dueño lo marcó el 12 de noviembre de 2026 y pidió
      // elegir entre la lista o un botón; es **la lista**, porque la pregunta que trae a
      // alguien a esta pantalla es «¿qué le estamos prestando a este cliente?» y un botón
      // la contesta mandándote a otro sitio.
      final r = await montar(
        tester,
        conSusServicios: true,
        servicios: [
          unServicio(codigo: 'SRV-000001', nombre: 'Sportium Satélite'),
          unServicio(
            codigo: 'SRV-000002',
            nombre: 'Sportium Interlomas',
            id: '0193f0a0-0000-7000-8000-0000000000a2',
            // DENTRO DE LOS TREINTA DÍAS desde el 12 de noviembre.
            termino: '2026-11-30',
          ),
        ],
      );

      expect(find.text('SRV-000001'), findsOneWidget);
      expect(find.text('Sportium Satélite'), findsOneWidget);

      // Y LA MISMA INSIGNIA QUE EN EL LISTADO Y EL EXPEDIENTE, del mismo sitio.
      expect(find.text('Termina el 30/nov/2026'), findsOneWidget);

      // SE PIDE UNO MÁS DE LOS QUE SE ENSEÑAN, que es cómo se sabe si hay más sin
      // contar: el listado pagina por cursor y no devuelve totales.
      final pedido = r.pedidas.singleWhere(
        (p) => p.url.path.endsWith('/services'),
      );

      expect(pedido.url.queryParameters['clientId'], clienteId);
      expect(pedido.url.queryParameters['limit'], '6');

      // Y CADA UNO SE ABRE desde aquí.
      await tester.tap(find.text('Abrir').first);
      await tester.pumpAndSettle();

      expect(r.abiertos, ['0193f0a0-0000-7000-8000-0000000000a1']);
    });

    testWidgets('sin servicios lo DICE, no deja el hueco', (tester) async {
      final r = await montar(tester, conSusServicios: true);

      expect(
        find.text('Este cliente todavía no tiene servicios'),
        findsOneWidget,
      );

      // Y EL BOTÓN SIGUE ESTANDO: desde ahí se le da de alta uno.
      await tester.tap(find.text('Ver en Servicios'));
      await tester.pumpAndSettle();

      expect(r.abiertos, ['todos']);
    });

    testWidgets('publica el nombre para el rastro, con su folio', (
      tester,
    ) async {
      final r = await montar(tester);

      // SALE DE LA FILA CARGADA Y NUNCA DE LA URL: en la URL quedaría viejo en cuanto
      // alguien renombrara al cliente.
      expect(r.nombres, ['CLI-000004 Sportium']);
    });

    testWidgets('con UNA entidad fiscal activa dice su razón social y su RFC', (
      tester,
    ) async {
      await montar(
        tester,
        entidades: [
          laEntidad(id: 'e1', razon: 'Sportium Club SA de CV'),
          // UNA ARCHIVADA NO CUENTA: no se borra —con ella se emitieron facturas— y
          // tampoco es con la que se factura hoy.
          laEntidad(id: 'e2', razon: 'Vieja SA', estatus: 'archived'),
        ],
      );

      // SE ACOTA A LA FICHA, y hace falta: la seccion de entidades fiscales pinta la
      // misma razon social mas abajo, asi que buscar el texto a secas no distinguiria
      // «la ficha la muestra» —que es la regla— de «la lista la lista», que es siempre.
      expect(enLaFicha('Sportium Club SA de CV'), findsOneWidget);
      expect(enLaFicha('SPO210101AAA'), findsOneWidget);
    });

    testWidgets('con DOS activas no dice ninguna, porque sería ambiguo', (
      tester,
    ) async {
      // ⚠️ ES LA REGLA DEL ESCRITORIO Y ES CORRECTA: la ficha no elige una, y enseñar
      // «la primera» sería inventar con qué razón social se factura.
      await montar(
        tester,
        entidades: [
          laEntidad(id: 'e1', razon: 'Sportium Club SA de CV'),
          laEntidad(id: 'e2', razon: 'Sportium Norte SA de CV'),
        ],
      );

      // LA CABECERA NO DICE NINGUNA —no elige— y la LISTA dice las dos, que es lo
      // correcto: lo ambiguo es facturar, no existir.
      expect(find.byKey(claveDeLaEntidadDeLaFicha), findsNothing);

      await abrirPestana(tester, 'Razones sociales');

      expect(find.text('Sportium Club SA de CV'), findsOneWidget);
      expect(find.text('Sportium Norte SA de CV'), findsOneWidget);
    });

    testWidgets('sin ninguna entidad fiscal tampoco', (tester) async {
      await montar(tester);

      expect(find.byKey(claveDeLaEntidadDeLaFicha), findsNothing);
      expect(find.text('SPO210101AAA'), findsNothing);
    });

    testWidgets('una entidad activa SIN RFC lo dice, no lo deja en blanco', (
      tester,
    ) async {
      // El RFC es opcional al dar de alta la entidad —la constancia llega después— y
      // **obligatorio para facturar**. Un hueco en blanco no avisaría de nada.
      await montar(
        tester,
        entidades: [laEntidad(id: 'e1', razon: 'Sportium SA', rfc: null)],
      );

      expect(enLaFicha('Sin RFC registrado'), findsOneWidget);
    });

    testWidgets('sin permiso de administrar no hay botones de escritura', (
      tester,
    ) async {
      await montar(tester, capacidades: soloLeer);

      expect(find.text('Editar'), findsNothing);
      expect(find.text('Cambiar estatus'), findsNothing);
      expect(find.text('Editar logotipo'), findsNothing);
    });
  });

  // =========================================================================
  group('los indicadores', () {
    testWidgets('dicen los servicios activos', (tester) async {
      await montar(tester);

      // ⚠️ **AHORA SON CIFRAS DE LA CABECERA**, y sus etiquetas van en versalita: el
      // estilo B las sube junto al nombre —que es donde se mira primero— en vez de
      // dejar dos tarjetas grandes empujando el resto de la pantalla hacia abajo.
      expect(find.text('SERVICIOS ACTIVOS'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('sin condiciones vigentes NO dice cero pesos', (tester) async {
      // ⚠️ **VACÍA NO ES CERO.** Un `$0.00` diría que se contrató algo por cero pesos,
      // que es una respuesta creíble y falsa.
      await montar(tester);

      expect(find.text('Sin condiciones vigentes'), findsOneWidget);
      expect(find.textContaining(r'$0.00'), findsNothing);
    });

    testWidgets('el importe sale con separadores y su moneda', (tester) async {
      await montar(
        tester,
        importes: const [Monto(moneda: 'MXN', menores: 123456789)],
      );

      expect(find.text(r'$1,234,567.89 MXN'), findsOneWidget);
    });

    testWidgets('dos monedas NO se suman', (tester) async {
      // Es la decisión del servidor y la pantalla la respeta: el día que un cliente
      // tenga condiciones en dos monedas, sumar pesos con dólares daría un número que
      // no significa nada.
      await montar(
        tester,
        importes: const [
          Monto(moneda: 'MXN', menores: 100000),
          Monto(moneda: 'USD', menores: 50000),
        ],
      );

      expect(find.textContaining(r'$1,000.00 MXN'), findsOneWidget);
      expect(find.textContaining(r'$500.00 USD'), findsOneWidget);
    });

    testWidgets('la letra chica dice QUÉ cuenta el importe', (tester) async {
      await montar(tester);

      // LA LETRA CHICA ES LA NOTA DE LA CIFRA, debajo del importe: con el estilo B el
      // indicador y lo que explica viven juntos.
      expect(
        find.text('Sin IVA, de los servicios no terminados.'),
        findsOneWidget,
      );
    });

    testWidgets('si no se pudieron leer, se dice en vez de poner ceros', (
      tester,
    ) async {
      await montar(
        tester,
        responder: (p) => p.url.path.endsWith('/indicators')
            ? http.Response('{}', 500)
            : null,
      );

      // SE DICE EN LA CIFRA, en su sitio: un «0 servicios» inventado sería un dato falso
      // con la forma de un dato.
      expect(find.text('INDICADORES'), findsOneWidget);
      expect(find.text('No se pudieron leer'), findsOneWidget);
      // Y LA FICHA SIGUE SIENDO ÚTIL: un cliente que no se puede consultar porque un
      // indicador no bajó sería una pantalla inútil por un adorno.
      expect(find.text('Sportium'), findsWidgets);
    });
  });

  // =========================================================================
  group('consultar no es editar', () {
    testWidgets('🚫 en consulta NO HAY UN SOLO CAMPO: se lee como texto', (
      tester,
    ) async {
      // 🚫 **ERA EL CUARTO PROBLEMA QUE EL DUEÑO VIO EN PANTALLA** —«la vista se ve casi
      // igual que la edición»—, y lo que lo producía era medir esto al revés: antes la
      // prueba exigía que los campos estuvieran **apagados**, así que la pantalla
      // correcta era la que los tenía.
      //
      // Un cuadro gris con el dato dentro parece un campo que no te dejan tocar, no un
      // dato: la gente intenta escribir en él antes de entender que está consultando.
      await montar(tester);

      expect(find.byType(TextField), findsNothing);

      // Y EL DATO SE LEE IGUAL, que es lo que no se puede perder al quitar los cuadros.
      expect(find.text('Sportium'), findsWidgets);
      expect(find.text('CLI-000004'), findsWidgets);
    });

    testWidgets('el folio no se edita NUNCA, ni en edición', (tester) async {
      await montar(tester, editando: true);

      // NI SIQUIERA APAGADO: lo asigna el servidor y no viaja en ningún cuerpo, así que
      // en los dos modos es un dato. Un cuadro deshabilitado sólo invitaba a intentarlo.
      expect(find.text('Folio'), findsOneWidget);
      expect(find.text('CLI-000004'), findsWidgets);

      final campos = tester
          .widgetList<TextField>(find.byType(TextField))
          .where((c) => (c.controller?.text ?? '') == 'CLI-000004');

      expect(campos, isEmpty);
    });

    testWidgets('en edición el nombre sí', (tester) async {
      await montar(tester, editando: true);

      final nombre = tester.widget<TextField>(campoDe('Nombre comercial'));

      expect(nombre.enabled, isTrue);
    });
  });

  // =========================================================================
  group('guardar', () {
    testWidgets('sólo viaja lo que cambió, y con el motivo', (tester) async {
      final r = await montar(tester, editando: true);

      await tester.enterText(campoDe('Nombre comercial'), 'Sportium Norte');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar').first);
      await tester.pumpAndSettle();

      await darElMotivo(tester, 'Cambió de razón comercial');

      final patch = delCliente(r.pedidas, 'PATCH').single;

      expect(patch.json['commercialName'], 'Sportium Norte');
      expect(patch.json['reason'], 'Cambió de razón comercial');

      // ⚠️ LAS OBSERVACIONES NO VIAJAN porque no se tocaron. El servidor compara contra
      // la fila, y mandar un campo que no cambió es pedir permiso para algo que no se
      // está haciendo.
      expect(patch.json.containsKey('notes'), isFalse);
      expect(patch.json.containsKey('startedOn'), isFalse);
    });

    testWidgets('🚫 guardar VUELVE A LA FICHA y deja la guardia limpia', (
      tester,
    ) async {
      // 🚫 **LA FALLA QUE EL DUEÑO VIO EN PANTALLA EL 12 DE NOVIEMBRE DE 2026.** Guardaba,
      // leía «Se guardó el expediente del cliente», **la pantalla se quedaba en
      // `/editar`** y al salir le preguntaban si quería tirar lo que acababa de guardar.
      //
      // ⚠️ **Y NINGUNA PRUEBA PODÍA VERLO**, porque el router de este archivo **no tenía
      // `onExit`**: montaba dos rutas que no preguntan nunca. Guardar navegaba y nadie
      // consultaba a la guardia. Es el mismo tipo de hueco que D-56: dos piezas correctas
      // por separado y nadie midiendo el cruce.
      final r = await montar(tester, editando: true);

      await tester.enterText(campoDe('Nombre comercial'), 'Sportium Norte');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar').first);
      await tester.pumpAndSettle();
      await darElMotivo(tester, 'Cambió de razón comercial');

      // NI UN DIÁLOGO: lo que se guardó no es trabajo sin guardar.
      expect(find.text('¿Salir sin guardar?'), findsNothing);

      // Y SE VUELVE AL MODO VISTA, que es lo que la persona quería al pulsar Guardar.
      expect(r.router.state.uri.path, '/comercial/clientes/$clienteId');
      expect(find.byType(TextField), findsNothing);

      // Y AL SALIR DE VERDAD TAMPOCO PREGUNTA: es la mitad que el dueño vio rota.
      r.router.go('/comercial/clientes/$otroCliente');
      await tester.pumpAndSettle();

      expect(find.text('¿Salir sin guardar?'), findsNothing);
      expect(
        r.router.state.uri.path,
        '/comercial/clientes/$otroCliente',
      );
    });

    testWidgets('D-58 · el inicio de la relación YA SE EDITA y viaja solo', (
      tester,
    ) async {
      // ✅ **D-58 PARTE 2.** El servidor aceptaba `startedOn` en el `PATCH` desde
      // siempre; lo que faltaba era el selector, y mientras tanto el campo decía el dato
      // sin dejar corregirlo. Ahora se corrige, y **viaja solo**: cambiar la fecha no
      // arrastra el nombre ni las observaciones.
      final r = await montar(tester, editando: true);

      // ⚠️ **SE TOCA EL CAMPO, NO LA ETIQUETA.** `RisegDateField` pinta el `Text` de la
      // etiqueta y debajo el campo, **hermanos** dentro de una `Column`: tocar la
      // etiqueta no abre nada, y el fallo se lee como «no encuentro el día 15», que no
      // se parece en nada a su causa. Es la misma trampa que ya costó una tarde con
      // `RisegTextField`.
      await tester.tap(campoDe('Inicio de la relación'));
      await tester.pumpAndSettle();

      // El selector de Material abre en el mes de la fecha cargada —marzo de 2025—, así
      // que el día 15 está a la vista sin navegar.
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar').first);
      await tester.pumpAndSettle();

      await darElMotivo(tester, 'La relación empezó antes de lo capturado');

      final patch = delCliente(r.pedidas, 'PATCH').single;

      expect(patch.json['startedOn'], '2025-03-15');
      expect(patch.json['reason'], 'La relación empezó antes de lo capturado');

      // Y NADA MÁS: el nombre y las observaciones no se tocaron.
      expect(patch.json.containsKey('commercialName'), isFalse);
      expect(patch.json.containsKey('notes'), isFalse);
    });

    testWidgets('vaciar las observaciones SÍ viaja, como nulo', (tester) async {
      // ⚠️ VACIARLAS Y NO TOCARLAS SE ESCRIBEN IGUAL EN JSON —`notes` ausente o nulo—
      // así que hace falta decir cuál es. Sin distinguirlo, no habría forma de borrar
      // unas observaciones.
      final r = await montar(tester, editando: true);

      await tester.enterText(campoDe('Observaciones'), '');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar').first);
      await tester.pumpAndSettle();
      await darElMotivo(tester, 'Ya no aplican');

      final patch = delCliente(r.pedidas, 'PATCH').single;

      expect(patch.json.containsKey('notes'), isTrue);
      expect(patch.json['notes'], isNull);
    });

    testWidgets('cancelar el motivo no manda nada y no pierde lo escrito', (
      tester,
    ) async {
      final r = await montar(tester, editando: true);

      await tester.enterText(campoDe('Nombre comercial'), 'Sportium Norte');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Seguir editando'));
      await tester.pumpAndSettle();

      expect(delCliente(r.pedidas, 'PATCH'), isEmpty);
      expect(find.text('Sportium Norte'), findsOneWidget);
    });

    testWidgets('sin cambios no manda nada ni pide motivo', (tester) async {
      // El servidor contestaría «No hay nada que modificar», que es un error por algo
      // que no es un error: se vuelve a la consulta, que es lo que esa persona quería.
      final r = await montar(tester, editando: true);

      await tester.tap(find.text('Guardar').first);
      await tester.pumpAndSettle();

      expect(delCliente(r.pedidas, 'PATCH'), isEmpty);
      expect(find.text('Motivo de la corrección'), findsNothing);
    });

    testWidgets('el nombre vacío se para aquí', (tester) async {
      final r = await montar(tester, editando: true);

      await tester.enterText(campoDe('Nombre comercial'), '   ');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar').first);
      await tester.pumpAndSettle();

      expect(find.text('Falta el nombre comercial.'), findsOneWidget);
      expect(delCliente(r.pedidas, 'PATCH'), isEmpty);
    });
  });

  // =========================================================================
  group('el domicilio de referencia', () {
    testWidgets('sin domicilio, la letra chica dice que es opcional', (
      tester,
    ) async {
      // ⚠️ **EN EDICIÓN, Y ES LO CORRECTO:** la regla de qué hace falta escribir sólo
      // importa cuando se está escribiendo. En consulta la nota dice lo que un domicilio
      // de referencia ES —y no dónde se presta un servicio—, que es lo que ahí hace
      // falta saber.
      await montar(tester, editando: true);
      await abrirPestana(tester, 'Domicilio');

      expect(
        find.textContaining('si lo dejas todo vacío, no se guarda domicilio'),
        findsOneWidget,
      );
    });

    testWidgets('con domicilio, dice que NO se puede quitar desde aquí', (
      tester,
    ) async {
      // ⚠️ ES DEL CONTRATO: el servidor no tiene `DELETE` de domicilio y su `PUT` exige
      // los seis obligatorios. En el escritorio vaciarlo lo archivaba. Decirlo evita
      // que se descubra con un «Falta la calle.».
      await montar(tester, editando: true, domicilio: elDomicilio());
      await abrirPestana(tester, 'Domicilio');

      expect(
        find.textContaining('no se puede quitar desde aquí'),
        findsOneWidget,
      );
    });

    testWidgets('en CONSULTA el domicilio se lee como texto, no en cuadros', (
      tester,
    ) async {
      // 🚫 **ERA EL CUARTO PROBLEMA DEL DUEÑO**: «la vista se ve casi igual que la
      // edición». Diez `RisegTextField` apagados con el domicilio dentro parecen campos
      // que no te dejan tocar, no un domicilio.
      await montar(tester, domicilio: elDomicilio());
      await abrirPestana(tester, 'Domicilio');

      // NI UN SOLO CAMPO, y la calle con su número en una línea: nadie lee un domicilio
      // campo por campo.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Av. Reforma 222'), findsOneWidget);
      expect(find.text('Juárez'), findsOneWidget);
    });

    testWidgets('escribir un domicilio nuevo va por PUT a su ruta', (
      tester,
    ) async {
      final r = await montar(tester, editando: true);
      await abrirPestana(tester, 'Domicilio');

      for (final (etiqueta, valor) in const [
        ('Calle', 'Av. Reforma'),
        ('Número exterior', '222'),
        ('Colonia', 'Juárez'),
        ('Municipio', 'Cuauhtémoc'),
        ('Estado', 'Ciudad de México'),
        ('Código postal', '06600'),
      ]) {
        await tester.enterText(campoDe(etiqueta), valor);
      }
      await tester.pumpAndSettle();

      // «GUARDAR» ESTÁ EN LA CABECERA, así que se pulsa desde cualquier pestaña.
      await tester.tap(find.text('Guardar').first);
      await tester.pumpAndSettle();
      await darElMotivo(tester, 'Llegó su domicilio');

      final put = r.pedidas.firstWhere((p) => p.metodo == 'PUT');

      expect(put.url.path, endsWith('/clients/$clienteId/address'));
      expect(put.json['street'], 'Av. Reforma');
      expect(put.json['postalCode'], '06600');

      // Y NO SE MANDÓ EL `PATCH`: el cliente no cambió, sólo su domicilio.
      expect(delCliente(r.pedidas, 'PATCH'), isEmpty);
    });

    testWidgets('vaciar un domicilio existente NO se manda, y se explica', (
      tester,
    ) async {
      final r = await montar(
        tester,
        editando: true,
        domicilio: elDomicilio(),
      );
      await abrirPestana(tester, 'Domicilio');

      for (final etiqueta in const [
        'Calle',
        'Número exterior',
        'Colonia',
        'Municipio',
        'Estado',
        'Código postal',
        'País',
      ]) {
        await tester.enterText(campoDe(etiqueta), '');
      }
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar').first);
      await tester.pumpAndSettle();
      await darElMotivo(tester, 'Ya no aplica');

      expect(r.pedidas.where((p) => p.metodo == 'PUT'), isEmpty);
      expect(
        find.textContaining('no se puede quitar desde aquí'),
        findsWidgets,
      );
    });

    testWidgets(
      'si el cliente se guarda y el domicilio falla, se dice qué quedó',
      (tester) async {
        // ⚠️ SON DOS RUTAS Y NO HAY UNA QUE ESCRIBA LAS DOS COSAS EN UNA TRANSACCIÓN.
        // Callarlo dejaría a alguien reescribiendo el nombre que ya se guardó.
        //
        // ⚠️ **EL RECHAZO ES UNA REGLA QUE LA PANTALLA NO COMPRUEBA**, y eso es a
        // propósito desde el 11 de noviembre de 2026: lo que falta por capturar ya se
        // señala en su campo **sin ir al servidor**, así que vaciar la colonia ya no
        // produce ningún `PUT` y esta prueba mediría otra cosa. El tope de caracteres sí
        // lo impone sólo el servidor —la pantalla no duplica sus longitudes— y por eso
        // sirve para medir lo que esto mide: qué se dice cuando la segunda ruta falla.
        final r = await montar(
          tester,
          editando: true,
          domicilio: elDomicilio(),
          responder: (p) => p.metodo == 'PUT'
              ? http.Response(
                  elError(
                    'validation_error',
                    'La colonia admite hasta 120 caracteres.',
                  ),
                  400,
                )
              : null,
        );

        await tester.enterText(campoDe('Nombre comercial'), 'Sportium Norte');
        await abrirPestana(tester, 'Domicilio');
        await tester.enterText(campoDe('Colonia'), 'Juárez Centro');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Guardar').first);
        await tester.pumpAndSettle();
        await darElMotivo(tester, 'Corrección');

        expect(delCliente(r.pedidas, 'PATCH'), hasLength(1));
        expect(
          find.textContaining('Se guardaron los datos del cliente, pero el '
              'domicilio no'),
          findsOneWidget,
        );
      },
    );

    testWidgets('🚫 lo que falta del domicilio se señala TODO, de un golpe', (
      tester,
    ) async {
      // 🚫 **LA FALLA DEL 11 DE NOVIEMBRE DE 2026 EN ESTA PANTALLA.** El domicilio iba
      // con `erroresPorCampo: const {}` y lo que faltaba se descubría **de uno en uno**
      // en el aviso del servidor, que contesta el primero que falta y para.
      final r = await montar(
        tester,
        editando: true,
        domicilio: elDomicilio(),
      );

      await abrirPestana(tester, 'Domicilio');
      await tester.enterText(campoDe('Estado'), '');
      await tester.enterText(campoDe('Código postal'), '');
      await tester.pumpAndSettle();

      // SE VUELVE A «GENERAL» A PROPÓSITO, para medir la pieza que el estilo B obligó a
      // añadir: guardar desde otra pestaña tiene que **abrir la del error**, o el aviso
      // se pintaría donde nadie está mirando.
      await abrirPestana(tester, 'General');
      await tester.tap(find.text('Guardar').first);
      await tester.pumpAndSettle();

      expect(find.text('Falta el estado.'), findsOneWidget);
      expect(find.text('Falta el código postal.'), findsOneWidget);

      // NI MOTIVO NI PETICIONES: preguntar el motivo de una corrección que no se va a
      // poder guardar es hacer escribir para nada.
      expect(find.text('Motivo de la corrección'), findsNothing);
      expect(r.pedidas.where((p) => p.metodo == 'PUT'), isEmpty);
      expect(delCliente(r.pedidas, 'PATCH'), isEmpty);
    });

  });

  // =========================================================================
  group('el estatus', () {
    testWidgets('el actual no se puede elegir', (tester) async {
      // Cambiarlo a sí mismo escribiría un evento en la bitácora que no cambió nada.
      await montar(tester);

      await tester.tap(find.text('Cambiar estatus'));
      await tester.pumpAndSettle();

      final activo = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Activo'),
      );

      expect(activo.enabled, isFalse);
    });

    testWidgets('cambiarlo manda el estatus y el motivo, y avisa', (
      tester,
    ) async {
      final r = await montar(tester);

      await tester.tap(find.text('Cambiar estatus'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Suspendido'));
      await tester.pumpAndSettle();

      // LA ADVERTENCIA SALE ANTES DE CONFIRMAR, no después: un cliente que no está
      // activo no admite servicios nuevos.
      expect(
        find.textContaining('no se le pueden crear servicios nuevos'),
        findsOneWidget,
      );

      // Y NO PROMETE MÁS DE LO QUE PASA. El texto decía «ni editar los que tiene», que
      // contradice la decisión del dueño —se bloquea crear, no editar— y describía una
      // restricción que el servidor no aplica. Las dos mitades se afirman juntas: que
      // avise de lo que sí ocurre, y que no avise de lo que no.
      expect(find.textContaining('ni editar los que tiene'), findsNothing);
      expect(
        find.textContaining('se siguen pudiendo editar'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField).last, 'Dejó de pagar');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cambiar el estatus'));
      await tester.pumpAndSettle();

      final patch = delCliente(r.pedidas, 'PATCH').single;

      expect(patch.json['status'], 'suspended');
      expect(patch.json['reason'], 'Dejó de pagar');
      expect(patch.json.containsKey('commercialName'), isFalse);
    });
  });

  // =========================================================================
  group('D-56 · el expediente declara lo que se perdería', () {
    testWidgets('en CONSULTA no hay nada que perder', (tester) async {
      // Los campos no se pueden tocar, así que una diferencia sólo podría venir de un
      // volcado a medias — y preguntar por eso sería preguntar por nada.
      final guardia = GuardiaDeSalida();

      await montar(tester, guardia: guardia, domicilio: elDomicilio());

      expect(guardia.hayCambiosSinGuardar, isFalse);
    });

    testWidgets('recién abierta la edición tampoco, con todo cargado', (
      tester,
    ) async {
      final guardia = GuardiaDeSalida();

      await montar(
        tester,
        guardia: guardia,
        editando: true,
        domicilio: elDomicilio(),
      );

      expect(
        guardia.hayCambiosSinGuardar,
        isFalse,
        reason: 'lo volcado es lo cargado: nadie ha escrito nada',
      );
    });

    testWidgets('escribir el nombre sí, y la pregunta nombra al cliente', (
      tester,
    ) async {
      final guardia = GuardiaDeSalida();

      await montar(tester, guardia: guardia, editando: true);

      await tester.enterText(campoDe('Nombre comercial'), 'Sportium Norte');
      await tester.pumpAndSettle();

      expect(guardia.hayCambiosSinGuardar, isTrue);

      // **EL NOMBRE GUARDADO Y NO EL DEL CAMPO**: a quien está renombrando, la pregunta
      // le hablaría de algo que todavía no existe con ese nombre.
      //
      // Y NOMBRA LO QUE SE DESCARTA, no «el expediente»: los contactos y las razones
      // sociales ya están escritos, cada uno por su ruta, y la frase lo dice para que la
      // pregunta no insinúe un deshacer que no existe.
      expect(
        guardia.queSePierde,
        'los datos del cliente Sportium: sus contactos y razones sociales ya están '
        'guardados',
      );
    });

    testWidgets('las secciones que se guardan solas lo DICEN, y «Guardar» dice su alcance', (
      tester,
    ) async {
      // LO QUE ESTO PROTEGE, y lo cazaron las pruebas en pantalla de C1: agregar un
      // contacto y pulsar «Cancelar» deja el contacto puesto. Es lo correcto —cada acto
      // tiene su ruta y no hay transacción que abarque la pantalla— y era justo lo que la
      // pantalla no decía.
      await montar(tester, editando: true);

      // ⚠️ **UNA POR PESTAÑA, y es el estilo B**: con los contactos y las razones
      // sociales en pestañas distintas, cada aviso vive donde está su sección. Antes
      // estaban las dos apiladas en la misma página.
      await abrirPestana(tester, 'Contactos');
      expect(find.textContaining('Se guarda al momento'), findsOneWidget);

      await abrirPestana(tester, 'Razones sociales');
      expect(find.textContaining('Se guarda al momento'), findsOneWidget);

      // Y EL ALCANCE DE «GUARDAR» SE LEE EN LAS CUATRO: vive bajo las pestañas, porque
      // el botón está en la cabecera y no al pie de una sola.
      //
      // ⚠️ **EN UNA LÍNEA, y nombrando lo que SÍ abarca** (12-nov-2026): la frase
      // enumeraba lo que no —«los contactos y las razones sociales ya están
      // guardados»— y era larga; nombrar las dos pestañas que espera dice lo mismo y se
      // lee de un vistazo.
      expect(
        find.text('«Guardar» aplica a General y Domicilio.'),
        findsOneWidget,
      );
    });

    testWidgets('en consulta las secciones avisan igual, porque se comportan igual', (
      tester,
    ) async {
      // LA OTRA MITAD DE LA DECISIÓN: no se esconden ni cambian en consulta. Si sólo
      // avisaran en edición, el aviso parecería una propiedad del modo y no de la
      // sección.
      await montar(tester, editando: false);

      await abrirPestana(tester, 'Contactos');
      expect(find.textContaining('Se guarda al momento'), findsOneWidget);

      await abrirPestana(tester, 'Razones sociales');
      expect(find.textContaining('Se guarda al momento'), findsOneWidget);

      // Y el alcance de «Guardar» NO sale, porque en consulta no hay botones que acotar.
      expect(find.textContaining('«Guardar» aplica'), findsNothing);
    });

    testWidgets('tocar el domicilio también cuenta', (tester) async {
      final guardia = GuardiaDeSalida();

      await montar(
        tester,
        guardia: guardia,
        editando: true,
        domicilio: elDomicilio(),
      );

      await abrirPestana(tester, 'Domicilio');
      await tester.enterText(campoDe('Colonia'), 'Roma Norte');
      await tester.pumpAndSettle();

      // ⚠️ **Y SIGUE CONTANDO AL CAMBIAR DE PESTAÑA**, que es lo que de verdad protege:
      // los controladores viven en el `State` de la pantalla, no en la pestaña, así que
      // lo escrito en Domicilio no se pierde ni deja de contar por irse a General.
      await abrirPestana(tester, 'General');

      expect(guardia.hayCambiosSinGuardar, isTrue);
    });

    testWidgets('escribir y deshacer NO es un cambio', (tester) async {
      // La trampa de D-56: una pregunta que sale por nada enseña a contestar el diálogo
      // sin leerlo.
      final guardia = GuardiaDeSalida();

      await montar(tester, guardia: guardia, editando: true);

      await tester.enterText(campoDe('Nombre comercial'), 'Sportiumm');
      await tester.pumpAndSettle();
      expect(guardia.hayCambiosSinGuardar, isTrue);

      await tester.enterText(campoDe('Nombre comercial'), 'Sportium');
      await tester.pumpAndSettle();
      expect(guardia.hayCambiosSinGuardar, isFalse);
    });
  });

  // =========================================================================
  group('el logotipo', () {
    testWidgets('elegirlo lo sube por PUT a la ruta del logotipo', (
      tester,
    ) async {
      final r = await montar(
        tester,
        selector: (_, {required donde, queReemplaza}) async =>
            LogotipoElegido(nombre: 'logo.png', bytes: Uint8List(8)),
        responder: (p) => p.metodo == 'PUT'
            ? http.Response(jsonEncode({'fileId': 'x'}), 200)
            : null,
      );

      await tester.tap(find.text('Editar logotipo'));
      await tester.pumpAndSettle();

      final put = r.pedidas.firstWhere((p) => p.metodo == 'PUT');

      expect(put.url.path, endsWith('/clients/$clienteId/logo'));
    });
  });

  // =========================================================================
  group('el importe, en pantalla', () {
    test('los centavos van con dos dígitos siempre', () {
      expect(const Monto(moneda: 'MXN', menores: 5).enPantalla, r'$0.05 MXN');
      expect(const Monto(moneda: 'MXN', menores: 50).enPantalla, r'$0.50 MXN');
      expect(const Monto(moneda: 'MXN', menores: 100).enPantalla, r'$1.00 MXN');
    });

    test('los miles van con coma, y no sobra ninguna', () {
      expect(
        const Monto(moneda: 'MXN', menores: 100000).enPantalla,
        r'$1,000.00 MXN',
      );
      expect(
        const Monto(moneda: 'MXN', menores: 99999).enPantalla,
        r'$999.99 MXN',
      );
      expect(
        const Monto(moneda: 'MXN', menores: 123456789).enPantalla,
        r'$1,234,567.89 MXN',
      );
    });

    test('un negativo lleva el signo delante y no parte los centavos', () {
      // Dart define el resto de un negativo de una forma que no es la que se espera al
      // partir pesos y centavos por separado, así que el signo se saca antes.
      expect(
        const Monto(moneda: 'MXN', menores: -12350).enPantalla,
        r'-$123.50 MXN',
      );
    });

    test('cero es cero, y eso lo decide quien lo pinta', () {
      // El modelo sabe escribir un cero; **la pantalla decide no pintarlo** cuando la
      // lista viene vacía, porque vacía no es cero.
      expect(const Monto(moneda: 'MXN', menores: 0).enPantalla, r'$0.00 MXN');
    });
  });
}
