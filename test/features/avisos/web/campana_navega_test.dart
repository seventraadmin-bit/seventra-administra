// LA CAMPANA, DENTRO DEL ROUTER DE VERDAD Y DEL PORTÓN DE VERDAD.
//
// ===========================================================================
// 🚫 POR QUÉ EXISTE: LA SUITE ESTABA VERDE Y EN PANTALLA NO PASABA NADA
// ===========================================================================
//
// El dueño probando el 13 de noviembre de 2026 abrió la campana, pulsó la fila de un
// servicio por terminar y **no pasó nada**. Pulsó «Ver en su listado» y tampoco. Y
// `campana_de_avisos_test.dart` estaba verde con ocho pruebas, una de ellas titulada
// «una fila ABRE SU DESTINO».
//
// **Lo que aquella prueba medía era que se LLAMA a `alAbrir`**, con un contador por
// destino. Eso es la mitad: lo que la campana hace de verdad es `context.go(...)` a una
// dirección **que el portón compone**, y la dirección estaba mal — `comercial/servicios`
// en vez de `/comercial/servicios`, sin la barra inicial—. Una dirección relativa no casa
// con ninguna ruta, así que go_router no movía nada.
//
// ⚠️ **UN CONTADOR NO ES UN DESTINO.** Mientras la prueba inventara el `alAbrir`, el
// `alAbrir` de verdad podía decir cualquier cosa. Por eso aquí no se inventa nada: se
// monta **el portón** —que es quien compone las direcciones— dentro **del router**, se
// pulsa la fila como la pulsa una persona, y se mira **dónde acabó la dirección**.
//
// Es el mismo cruce que ya costó la falla del 11 de noviembre en el alta de servicios:
// dos suites verdes a los dos lados de la pieza que fallaba.

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/app/shell/router_web.dart';
import 'package:riseg_one/app/theme/modo_de_tema_web.dart';
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/api/api_client_autenticado.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/auth_api.dart';
import 'package:riseg_one/core/auth/gestor_de_sesion.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/company/almacen_company_recordada.dart';
import 'package:riseg_one/core/company/company_api.dart';
import 'package:riseg_one/core/company/company_remota.dart';
import 'package:riseg_one/core/company/gestor_de_company.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/logging/app_logger.dart';
import 'package:riseg_one/core/trabajo_sin_guardar/guardia_de_salida.dart';
import 'package:riseg_one/features/comercial/web/datos/clientes_repositorio_http.dart';
import 'package:riseg_one/features/comercial/web/datos/servicios_repositorio_http.dart';
import 'package:riseg_one/features/comercial/web/presentation/expediente_servicio_web_screen.dart';
import 'package:riseg_one/features/comercial/web/presentation/servicios_web_screen.dart';
import 'package:riseg_one/features/organizacion/web/datos/areas_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/empresas_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/expedientes_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/logotipo_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/puestos_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/sucursales_repositorio_http.dart';
import 'package:riseg_one/features/personal/web/datos/empleados_repositorio_http.dart';
import 'package:riseg_one/features/usuarios/web/datos/usuarios_repositorio_http.dart';
import 'package:riseg_one/features/usuarios/web/marca_seventra.dart';
import 'package:riseg_one/features/usuarios/web/porton_web.dart';

const _empresa = '0193f0a0-0000-7000-8000-0000000000e1';
const _organizacion = '0193f0a0-0000-7000-8000-0000000000aa';
const _cliente = '0193f0a0-0000-7000-8000-0000000000c1';
const _servicio = '0193f0a0-0000-7000-8000-0000000000a1';

class _SinSesion implements AlmacenSesionRemota {
  CredencialRemota? _guardada;

  @override
  Future<CredencialRemota?> leer() async => _guardada;

  @override
  Future<void> escribir(CredencialRemota credencial) async =>
      _guardada = credencial;

  @override
  Future<void> borrar() async => _guardada = null;
}

class _SinPreferencia implements AlmacenCompanyRecordada {
  const _SinPreferencia();

  @override
  Future<String?> leer() async => null;

  @override
  Future<void> escribir(String companyId) async {}

  @override
  Future<void> borrar() async {}
}

void main() {
  /// Las direcciones que el servidor de mentira recibió, **en orden**: con ellas se
  /// comprueba que «Ver todos» no sólo cambia la dirección, sino que la pantalla a la que
  /// lleva pide **lo mismo que la campana contó**.
  late List<Uri> pedidas;

  MockClient elServidor() => MockClient((peticion) async {
    pedidas.add(peticion.url);

    final ruta = peticion.url.path;

    http.Response json(String cuerpo, [int estado = 200]) => http.Response(
      cuerpo,
      estado,
      headers: const {'content-type': 'application/json'},
    );

    if (ruta.endsWith('/auth/login')) {
      return json('''
        {
          "accessToken": "token-de-prueba",
          "refreshToken": "refresco-de-prueba",
          "identityId": "0193f0a0-0000-7000-8000-000000000001",
          "sessionId": "0193f0a0-0000-7000-8000-000000000002",
          "accessExpiresAt": "2099-01-01T00:00:00Z",
          "refreshExpiresAt": "2099-01-01T00:00:00Z",
          "displayName": "Usuario de prueba",
          "email": "prueba@ejemplo.mx"
        }
      ''');
    }

    if (ruta.endsWith('/companies')) {
      return json('''
        [{
          "companyId": "$_empresa",
          "organizationId": "$_organizacion",
          "companyName": "RISEG Servicios",
          "organizationName": "Grupo RISEG",
          "role": "maestro",
          "status": "activa"
        }]
      ''');
    }

    if (ruta.endsWith('/context')) {
      return json('''
        {
          "companyId": "$_empresa",
          "organizationId": "$_organizacion",
          "companyName": "RISEG Servicios",
          "companyStatus": "active",
          "organizationName": "Grupo RISEG",
          "role": "maestro",
          "isMaestro": false,
          "restricted": false,
          "enabledModules": ["clients_services"],
          "effectivePermissions": ["clients_services.read"]
        }
      ''');
    }

    // LA FICHA DEL SERVICIO, que es a donde tiene que llevar la fila.
    if (ruta.endsWith('/services/$_servicio')) {
      return json('''
        {
          "id": "$_servicio",
          "clientId": "$_cliente",
          "code": "SRV-000001",
          "name": "PRUEBA AAAA",
          "serviceTypeId": "0193f0a0-0000-7000-8000-0000000000b1",
          "status": "active",
          "temporalCondition": "ending",
          "startedOn": "2024-03-01",
          "endedOn": "2026-11-18",
          "notes": null,
          "supervisorEmployeeId": null,
          "administrativeBranchId": null,
          "responsibleContactId": null,
          "fiscalEntityId": null,
          "createdAt": "2024-03-01T12:00:00Z",
          "updatedAt": "2026-11-01T12:00:00Z"
        }
      ''');
    }

    // EL LISTADO: una fila, la misma que avisa.
    if (ruta.endsWith('/services')) {
      return json('''
        {
          "items": [{
            "id": "$_servicio",
            "clientId": "$_cliente",
            "code": "SRV-000001",
            "name": "PRUEBA AAAA",
            "serviceTypeId": "0193f0a0-0000-7000-8000-0000000000b1",
            "status": "active",
            "temporalCondition": "ending",
            "startedOn": "2024-03-01",
            "endedOn": "2026-11-18",
            "clientCommercialName": "Sportium",
            "clientHasLogo": false,
            "clientLogoFileId": null,
            "location": "Naucalpan, Estado de México"
          }],
          "nextCursor": null
        }
      ''');
    }

    if (ruta.endsWith('/clients/$_cliente')) {
      return json('''
        {
          "id": "$_cliente",
          "code": "CLI-000001",
          "commercialName": "Sportium",
          "status": "active",
          "relationshipStartedOn": "2024-01-01",
          "notes": null,
          "createdAt": "2024-01-01T12:00:00Z",
          "updatedAt": "2024-01-01T12:00:00Z"
        }
      ''');
    }

    // LO QUE NO SE NOMBRA RESPONDE VACÍO EN VEZ DE 404: lo que esta prueba mide es a
    // dónde lleva la campana, no cómo se queja una tarjeta sin datos.
    if (ruta.endsWith('/logo')) return http.Response('', 404);
    if (ruta.endsWith('/membership')) return http.Response('', 404);
    if (ruta.endsWith('/indicators') || ruta.endsWith('/address')) {
      return http.Response('', 404);
    }

    return json('{"items": [], "nextCursor": null}');
  });

  /// Monta **el portón de verdad dentro del router de verdad**, con sesión y empresa
  /// resueltas, y devuelve el router para poder mirar la dirección.
  Future<GoRouter> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final desnudo = ApiClient(
      config: ApiConfig.resolve(raw: 'http://localhost:5199').when(
        ok: (c) => c,
        failure: (f) => throw StateError(f.message),
      ),
      cliente: elServidor(),
      logger: AppLogger.console(),
    );

    final sesion = GestorDeSesion(
      api: AuthApi(desnudo),
      almacen: _SinSesion(),
      logger: AppLogger.console(),
    );
    addTearDown(sesion.dispose);

    final autenticado = ApiClientAutenticado(cliente: desnudo, gestor: sesion);

    final company = GestorDeCompany(
      api: CompanyApi(autenticado),
      almacen: const _SinPreferencia(),
      logger: AppLogger.console(),
    );
    addTearDown(company.dispose);

    final guardia = GuardiaDeSalida();

    final router = construirRouterWeb(
      guardia: guardia,
      porton: PortonWeb(
        guardia: guardia,
        modoDeTema: ModoDeTemaWeb(),
        gestorDeSesion: sesion,
        gestorDeCompany: company,
        repositorioDeLogotipos: LogotipoRepositorioHttp(autenticado),
        repositorioDeAreas: AreasRepositorioHttp(autenticado),
        repositorioDeClientes: ClientesRepositorioHttp(autenticado),
        repositorioDeEmpresas: EmpresasRepositorioHttp(autenticado),
        repositorioDeExpedientes: ExpedientesRepositorioHttp(autenticado),
        repositorioDePuestos: PuestosRepositorioHttp(autenticado),
        repositorioDeServicios: ServiciosRepositorioHttp(autenticado),
        repositorioDeSucursales: SucursalesRepositorioHttp(autenticado),
        repositorioDeUsuarios: UsuariosRepositorioHttp(autenticado),
        repositorioDeEmpleados: EmpleadosRepositorioHttp(autenticado),
      ),
      gestores: losDosGestores(
        sesion.estadoObservable,
        company.estadoObservable,
      ),
      autoridad: () {
        final estado = company.estado;

        return estado is CompanyActiva
            ? (
                esMaestro: estado.contexto.isMaestro,
                permisos: estado.contexto.effectivePermissions,
              )
            : null;
      },
    );

    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: MarcaSeventra.tema(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );

    await tester.pump();

    final entrada = await sesion.iniciarSesion(
      email: 'prueba@ejemplo.mx',
      password: 'Contrasena-de-prueba-1',
    );

    entrada.when(
      ok: (_) {},
      failure: (f) => throw StateError('el login de prueba falló: ${f.message}'),
    );

    // SIN `pumpAndSettle`: mientras se resuelve la empresa el portón enseña una rueda, que
    // es una animación infinita. Se avanza cuadro a cuadro.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    return router;
  }

  Future<void> abrirLaCampana(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('campana_de_avisos')));

    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  setUp(() => pedidas = []);

  group('la campana lleva a donde dice', () {
    testWidgets('🚫 UNA FILA ABRE EL EXPEDIENTE DE SU SERVICIO', (tester) async {
      final router = await montar(tester);

      expect(
        find.byKey(const Key('campana_de_avisos')),
        findsOneWidget,
        reason: 'con permiso de Clientes y servicios la campana tiene que estar',
      );

      await abrirLaCampana(tester);

      expect(find.text('PRUEBA AAAA'), findsOneWidget);

      await tester.tap(find.text('PRUEBA AAAA'));

      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(
        router.state.uri.toString(),
        '/comercial/servicios/$_servicio',
        reason:
            'pulsar la fila tiene que MOVER LA DIRECCIÓN al expediente de ese '
            'servicio. Una dirección sin la barra inicial no casa con ninguna ruta '
            'y go_router se queda donde estaba, sin avisar.',
      );

      expect(find.byType(ExpedienteServicioWebScreen), findsOneWidget);
    });

    testWidgets('🚫 «VER TODOS» LLEVA A SERVICIOS CON EL GRUPO POR TERMINAR', (
      tester,
    ) async {
      final router = await montar(tester);

      await abrirLaCampana(tester);

      await tester.tap(find.text('Ver todos'));

      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(
        router.state.uri.toString(),
        '/comercial/servicios?grupo=porTerminar',
        reason: '«Ver todos» tiene que llevar al listado YA FILTRADO por lo mismo',
      );

      expect(find.byType(ServiciosWebScreen), findsOneWidget);

      // Y EL FILTRO LLEGA AL SERVIDOR, que es lo que hace que la lista sea la misma que
      // la campana contó: la dirección sin la petición sería un chip pintado.
      expect(
        pedidas.where((u) => u.queryParameters.containsKey('endingWithin')),
        isNotEmpty,
        reason:
            'el listado al que lleva «Ver todos» tiene que pedir los que terminan '
            'pronto, con la misma ventana que la campana',
      );
    });

    testWidgets('🚫 CAMBIAR DE PANTALLA VUELVE A PREGUNTAR, sin sondeo', (
      tester,
    ) async {
      // 🚫 **EL NÚMERO VIEJO DEL 13 DE NOVIEMBRE DE 2026.** El dueño quitó una fecha de
      // término y la campana siguió diciendo «1» hasta que la volvió a abrir: el número
      // se lee **sin abrir nada**, y un número viejo se cree.
      //
      // Lo que se mide aquí es la mitad que nadie podía ver desde la campana sola: que
      // **la dirección** la haga preguntar. La otra mitad —las acciones que mueven un
      // término sin cambiar de pantalla— vive en `servicios_expediente_test.dart`.
      final router = await montar(tester);

      /// Cuántas veces se ha preguntado por los que terminan pronto. **Es la lectura de
      /// la campana**: ninguna pantalla pide con esa ventana si no la eligió a mano.
      int lecturasDeLaCampana() => pedidas
          .where((u) => u.queryParameters['endingWithin'] == '30')
          .length;

      final alMontar = lecturasDeLaCampana();

      expect(
        alMontar,
        greaterThan(0),
        reason: 'la campana lee al montarse, o el número nacería vacío',
      );

      // Se cambia de pestaña como lo hace una persona: por la dirección.
      router.go('/comercial/servicios');

      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(
        lecturasDeLaCampana(),
        greaterThan(alMontar),
        reason:
            'al cambiar de pantalla la campana tiene que volver a preguntar: si no, '
            'el número se queda con lo que era verdad al entrar',
      );

      // 🚫 **Y NO ES UN SONDEO:** quieto, no pregunta nada. Lo dispara quien sabe que
      // algo cambió, no un reloj.
      final despuesDeNavegar = lecturasDeLaCampana();

      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }

      expect(lecturasDeLaCampana(), despuesDeNavegar);
    });
  });
}
