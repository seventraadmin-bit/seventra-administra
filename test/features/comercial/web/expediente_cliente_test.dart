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
import 'package:riseg_one/features/comercial/web/datos/clientes_repositorio_http.dart';
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
  Future<({List<_Pedida> pedidas, GoRouter router, List<String> nombres})> montar(
    WidgetTester tester, {
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
      importes: importes,
      responder: responder,
    );

    final nombres = <String>[];

    final router = GoRouter(
      initialLocation: editando
          ? '/comercial/clientes/$clienteId/editar'
          : '/comercial/clientes/$clienteId',
      routes: [
        GoRoute(
          path: '/comercial/clientes/:id',
          // LAS DOS DIRECCIONES, con la misma pantalla y `editando` distinto: es la
          // forma exacta que usa el portón, y montar sólo una mediría la mitad.
          builder: (contexto, estado) => ExpedienteClienteWebScreen(
            repositorio: ClientesRepositorioHttp(api),
            empresaId: empresa,
            clienteId: estado.pathParameters['id']!,
            capacidades: capacidades,
            guardia: guardia ?? GuardiaDeSalida(),
            editando: false,
            alIrADentro: (aDonde) => contexto.go(
              '/comercial/clientes/${estado.pathParameters['id']}'
              '${aDonde == null ? '' : '/$aDonde'}',
            ),
            alVolver: () {},
            alConocerElNombre: (_, nombre) => nombres.add(nombre),
            elegirUnLogotipo: selector ?? elegirLogotipo,
          ),
          routes: [
            GoRoute(
              path: 'editar',
              builder: (contexto, estado) => ExpedienteClienteWebScreen(
                repositorio: ClientesRepositorioHttp(api),
                empresaId: empresa,
                clienteId: estado.pathParameters['id']!,
                capacidades: capacidades,
                guardia: guardia ?? GuardiaDeSalida(),
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

    return (pedidas: pedidas, router: router, nombres: nombres);
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

      // LA FICHA NO DICE NINGUNA —no elige— y la LISTA de abajo dice las dos, que es lo
      // correcto: lo ambiguo es facturar, no existir.
      expect(find.byKey(claveDeLaEntidadDeLaFicha), findsNothing);

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

      expect(find.text('Servicios activos'), findsOneWidget);
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

      expect(
        find.text(
          'Importe mensual contratado, sin IVA, de los servicios no terminados.',
        ),
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

      expect(
        find.text('No se pudieron leer los indicadores de este cliente.'),
        findsOneWidget,
      );
      // Y LA FICHA SIGUE SIENDO ÚTIL: un cliente que no se puede consultar porque un
      // indicador no bajó sería una pantalla inútil por un adorno.
      expect(find.text('Sportium'), findsWidgets);
    });
  });

  // =========================================================================
  group('consultar no es editar', () {
    testWidgets('en consulta los campos no se pueden escribir', (tester) async {
      await montar(tester);

      final nombre = tester.widget<TextField>(campoDe('Nombre comercial'));

      expect(nombre.enabled, isFalse);
    });

    testWidgets('el folio no se edita NUNCA, ni en edición', (tester) async {
      await montar(tester, editando: true);

      final folio = tester.widget<TextField>(campoDe('Folio'));

      expect(folio.enabled, isFalse);
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
      await montar(tester);

      expect(
        find.textContaining('Si los dejas todos vacíos, no se guarda domicilio'),
        findsOneWidget,
      );
    });

    testWidgets('con domicilio, dice que NO se puede quitar desde aquí', (
      tester,
    ) async {
      // ⚠️ ES DEL CONTRATO: el servidor no tiene `DELETE` de domicilio y su `PUT` exige
      // los seis obligatorios. En el escritorio vaciarlo lo archivaba. Decirlo evita
      // que se descubra con un «Falta la calle.».
      await montar(tester, domicilio: elDomicilio());

      expect(
        find.textContaining('no se puede quitar desde aquí'),
        findsOneWidget,
      );
    });

    testWidgets('escribir un domicilio nuevo va por PUT a su ruta', (
      tester,
    ) async {
      final r = await montar(tester, editando: true);

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
        final r = await montar(
          tester,
          editando: true,
          domicilio: elDomicilio(),
          responder: (p) => p.metodo == 'PUT'
              ? http.Response(
                  elError('validation_error', 'Falta la colonia.'),
                  400,
                )
              : null,
        );

        await tester.enterText(campoDe('Nombre comercial'), 'Sportium Norte');
        await tester.enterText(campoDe('Colonia'), '');
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
      expect(guardia.queSePierde, 'el expediente del cliente Sportium');
    });

    testWidgets('tocar el domicilio también cuenta', (tester) async {
      final guardia = GuardiaDeSalida();

      await montar(
        tester,
        guardia: guardia,
        editando: true,
        domicilio: elDomicilio(),
      );

      await tester.enterText(campoDe('Colonia'), 'Roma Norte');
      await tester.pumpAndSettle();

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
