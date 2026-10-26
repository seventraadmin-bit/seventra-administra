// E3 — «Crea tu primera empresa», en pantalla y en el portón.
//
// QUÉ DEFIENDEN ESTAS PRUEBAS, en orden de importancia:
//
//  1. **que el mensaje de siempre siga saliendo para quien NO puede crear.** Es la
//     frontera de toda la etapa: el botón es la excepción, no el caso general, y
//     enseñárselo a un empleado al que todavía no le han dado acceso sería ofrecerle
//     una puerta que el servidor le va a cerrar;
//  2. **que un fallo de red NO se convierta en «no puedes»**, sino en «vuelve a
//     intentarlo». Es «ausencia nunca es cero» en el único sitio donde se nota;
//  3. **que la razón social del alta llegue al servidor**, porque hasta E3 se escribía,
//     se enviaba y se tiraba en silencio;
//  4. **que con varias organizaciones se pregunte en cuál**, que es la regla de E1-B
//     aplicada a dónde NACE una empresa.
//
// EL SEGUNDO GRUPO MONTA EL PORTÓN DE VERDAD, con su cliente HTTP contra un
// `MockClient`. No es ceremonia: la decisión de qué pantalla sale vive en el portón y
// depende de TRES respuestas del servidor encadenadas. Una prueba que llamara al método
// privado no habría cazado el defecto de verdad posible aquí —pedir la autoridad con un
// id que la respuesta vacía no trae—, porque ese id sólo existe si la segunda lectura se
// hizo.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/app/shell/router_web.dart';
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/api/api_client_autenticado.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/auth_api.dart';
import 'package:riseg_one/core/auth/gestor_de_sesion.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/company/almacen_company_recordada.dart';
import 'package:riseg_one/core/company/autoridad_de_organizacion.dart';
import 'package:riseg_one/core/company/company_api.dart';
import 'package:riseg_one/core/company/company_remota.dart';
import 'package:riseg_one/core/company/gestor_de_company.dart';
import 'package:riseg_one/core/company/guardia_de_salida.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/design_system/design_system_web.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/core/logging/app_logger.dart';
import 'package:riseg_one/features/organizacion/web/datos/areas_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/empresas_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/expedientes_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/logotipo_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/puestos_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/sucursales_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/modelos/empresa_administrada.dart';
import 'package:riseg_one/features/organizacion/web/modelos/organizacion_propia.dart';
import 'package:riseg_one/features/organizacion/web/presentation/primera_empresa_screen.dart';
import 'package:riseg_one/features/usuarios/web/datos/usuarios_repositorio_http.dart';
import 'package:riseg_one/features/usuarios/web/marca_seventra.dart';
import 'package:riseg_one/features/usuarios/web/porton_web.dart';

const _orgA = '0193f0a0-0000-7000-8000-0000000000aa';
const _orgB = '0193f0a0-0000-7000-8000-0000000000bb';

/// La empresa única del caso en que SÍ se entra: la prueba del ciclo de vida necesita
/// una empresa activa, que es el único estado en el que ponerse al día significa algo.
const _idUnica = '0193f0a0-0000-7000-8000-0000000000c1';

/// Lo que el servidor recibió, para poder afirmar sobre el cuerpo y no sólo sobre la
/// pantalla. Un alta que pinta bien y manda el campo equivocado es exactamente el
/// defecto que E3 vino a arreglar.
class _Alta {
  _Alta(this.organizationId, this.nombre, this.razonSocial);

  final String organizationId;
  final String nombre;
  final String? razonSocial;
}

class _RepositorioFalso implements EmpresasRepositorioHttp {
  _RepositorioFalso({this.fallo});

  /// Lo que responde `crear`. Nulo = sale bien.
  final Failure? fallo;

  final List<_Alta> altas = [];

  @override
  Future<Result<void>> crear({
    required String organizationId,
    required String nombre,
    String? maestroIdentityId,
    String? razonSocial,
  }) async {
    altas.add(_Alta(organizationId, nombre, razonSocial));

    final f = fallo;
    return f == null ? const Result.ok(null) : Result.failure(f);
  }

  // ---------------------------------------------------------------------------
  // Lo que esta pantalla NO usa. Lanzar es mejor que devolver vacío: si algún día
  // empieza a llamarlo, la prueba lo dice en vez de pasar con una respuesta inventada.
  // ---------------------------------------------------------------------------

  @override
  Future<Result<List<OrganizacionPropia>>> listarOrganizaciones() async =>
      throw UnimplementedError('la pantalla recibe las organizaciones resueltas');

  @override
  Future<Result<AutoridadDeOrganizacion?>> leerAutoridad(String organizationId) async =>
      throw UnimplementedError('la autoridad la resuelve el portón');

  @override
  Future<Result<List<EmpresaAdministrada>>> listar(String organizationId) async =>
      throw UnimplementedError('aquí no hay ninguna empresa que listar');

  @override
  Future<Result<void>> desactivar({
    required String organizationId,
    required String companyId,
    required String motivo,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> reactivar({
    required String organizationId,
    required String companyId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> descartar({
    required String organizationId,
    required String companyId,
    required String motivo,
  }) async => throw UnimplementedError();
}

Finder _botonDe(String etiqueta) => find.ancestor(
  of: find.text(etiqueta),
  matching: find.byType(RisegButton),
);

void main() {
  // =========================================================================
  group('La pantalla', () {
    Future<(_RepositorioFalso, List<String>)> montar(
      WidgetTester tester, {
      required List<OrganizacionPropia> organizaciones,
      Failure? fallo,
      String usuario = 'Marlon Rios',
    }) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repositorio = _RepositorioFalso(fallo: fallo);
      final creadas = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: MarcaSeventra.tema(),
          home: PrimeraEmpresaScreen(
            repositorio: repositorio,
            organizaciones: organizaciones,
            usuario: usuario,
            alCreada: () async => creadas.add('resuelta'),
            alCerrarSesion: () async {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      return (repositorio, creadas);
    }

    testWidgets('con UNA organización no pregunta nada y enseña el formulario', (
      tester,
    ) async {
      await montar(
        tester,
        organizaciones: const [
          OrganizacionPropia(organizationId: _orgA, nombre: 'Cliente de Prueba'),
        ],
      );

      expect(find.text('Crea tu primera empresa'), findsOneWidget);
      expect(find.byKey(const Key('alta_nombre')), findsOneWidget);

      // NO SE PREGUNTA DÓNDE, y tampoco se nombra la organización: con una sola, decir
      // «en Cliente de Prueba» sugiere una decisión que no hubo.
      expect(find.text('¿Dónde creas tu empresa?'), findsNothing);
      expect(find.byKey(const Key('primera_empresa_donde')), findsNothing);
    });

    testWidgets('con DOS organizaciones pregunta en cuál antes del formulario', (
      tester,
    ) async {
      // LA REGLA DE E1-B, aplicada a dónde NACE una empresa: con varias se pregunta
      // siempre. Elegir por omisión la primera de la lista sería crear el inquilino de
      // un cliente dentro de otro.
      await montar(
        tester,
        organizaciones: const [
          OrganizacionPropia(organizationId: _orgA, nombre: 'Cliente de Prueba'),
          OrganizacionPropia(organizationId: _orgB, nombre: 'Otro Cliente'),
        ],
      );

      expect(find.text('¿Dónde creas tu empresa?'), findsOneWidget);
      expect(find.byKey(const Key('alta_nombre')), findsNothing);

      await tester.tap(find.byKey(const Key('primera_empresa_org_$_orgB')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('alta_nombre')), findsOneWidget);

      // Y SE DICE DÓNDE, ahora que sí fue una decisión.
      expect(find.text('En Otro Cliente.'), findsOneWidget);
    });

    testWidgets('sin nombre no llama al servidor', (tester) async {
      final (repositorio, creadas) = await montar(
        tester,
        organizaciones: const [
          OrganizacionPropia(organizationId: _orgA, nombre: 'Cliente de Prueba'),
        ],
      );

      await tester.tap(_botonDe('Crear empresa y entrar'));
      await tester.pumpAndSettle();

      // NO ES POR AHORRAR UNA PETICIÓN: el 400 que contestaría el servidor es
      // indistinguible, para quien lo lee, de un problema de verdad.
      expect(repositorio.altas, isEmpty);
      expect(creadas, isEmpty);
    });

    testWidgets('crear manda el nombre Y LA RAZÓN SOCIAL, y luego resuelve', (
      tester,
    ) async {
      // ⚠️ ES EL DEFECTO QUE E3 DESTAPÓ, visto desde el cliente: la razón social se
      // escribía y no llegaba. Aquí se afirma sobre el CUERPO que sale, no sobre lo que
      // la pantalla pinta.
      final (repositorio, creadas) = await montar(
        tester,
        organizaciones: const [
          OrganizacionPropia(organizationId: _orgA, nombre: 'Cliente de Prueba'),
        ],
      );

      await tester.enterText(
        find.byKey(const Key('alta_nombre')),
        '  RISEG Servicios  ',
      );
      await tester.enterText(
        find.byKey(const Key('alta_razon_social')),
        'RISEG SERVICIOS SA DE CV',
      );
      await tester.pumpAndSettle();

      // SIN `pumpAndSettle`: en el camino feliz el botón se queda girando a propósito
      // —la empresa ya existe y el portón está a punto de desmontar esta pantalla—, y
      // un giro es una animación infinita. Avanzar cuadro a cuadro deja terminar la
      // petición sin esperar a que algo se quede quieto.
      await tester.tap(_botonDe('Crear empresa y entrar'));
      await tester.pump();
      await tester.pump();

      expect(repositorio.altas, hasLength(1));
      expect(repositorio.altas.single.organizationId, _orgA);
      expect(repositorio.altas.single.nombre, 'RISEG Servicios');
      expect(repositorio.altas.single.razonSocial, 'RISEG SERVICIOS SA DE CV');

      // Y SE PIDE RESOLVER: con una sola empresa el gestor entra directo en ella.
      expect(creadas, ['resuelta']);
    });

    testWidgets('la razón social en blanco viaja como AUSENTE, no como vacía', (
      tester,
    ) async {
      // La columna es nullable y su CHECK rechaza lo vacío, así que un `""` que llegara
      // al INSERT reventaría. El servidor lo normaliza igual; esto fija que el cliente
      // no mande basura y que la regla no dependa de un solo lado.
      final (repositorio, _) = await montar(
        tester,
        organizaciones: const [
          OrganizacionPropia(organizationId: _orgA, nombre: 'Cliente de Prueba'),
        ],
      );

      await tester.enterText(find.byKey(const Key('alta_nombre')), 'Sin razón');
      await tester.enterText(find.byKey(const Key('alta_razon_social')), '   ');
      await tester.pumpAndSettle();

      await tester.tap(_botonDe('Crear empresa y entrar'));
      await tester.pump();
      await tester.pump();

      expect(repositorio.altas.single.razonSocial, isNull);
    });

    testWidgets('el 409 de capacidad se enseña TAL CUAL, sin reescribirlo', (
      tester,
    ) async {
      // EL SERVIDOR MANDA LAS DOS CIFRAS —«tu plan permite N y quedarían M»— y
      // reescribir el mensaje las perdería. Esta pantalla NO dice cuánto incluye el
      // plan por su cuenta: no tiene de dónde sacarlo.
      final (_, creadas) = await montar(
        tester,
        organizaciones: const [
          OrganizacionPropia(organizationId: _orgA, nombre: 'Cliente de Prueba'),
        ],
        fallo: const ApiHttpFailure(
          statusCode: 409,
          codigo: 'capacity_exceeded',
          message: 'Tu plan permite 1 empresa y quedarían 2.',
        ),
      );

      await tester.enterText(find.byKey(const Key('alta_nombre')), 'La segunda');
      await tester.pumpAndSettle();

      await tester.tap(_botonDe('Crear empresa y entrar'));
      await tester.pumpAndSettle();

      expect(find.text('Tu plan permite 1 empresa y quedarían 2.'), findsOneWidget);

      // Y EL FORMULARIO SIGUE AHÍ: con capacidad libre, la misma petición funciona.
      expect(find.byKey(const Key('alta_nombre')), findsOneWidget);
      expect(creadas, isEmpty);
    });

    testWidgets('el 403 de autoridad se dice en palabras y no con el código', (
      tester,
    ) async {
      final (_, creadas) = await montar(
        tester,
        organizaciones: const [
          OrganizacionPropia(organizationId: _orgA, nombre: 'Cliente de Prueba'),
        ],
        fallo: const ApiHttpFailure(
          statusCode: 403,
          codigo: 'autoridad_insuficiente',
          message: 'No tienes autoridad para administrar empresas.',
        ),
      );

      await tester.enterText(find.byKey(const Key('alta_nombre')), 'La que no se crea');
      await tester.pumpAndSettle();

      await tester.tap(_botonDe('Crear empresa y entrar'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('ya no tiene autoridad para crear empresas'),
        findsOneWidget,
      );
      expect(creadas, isEmpty);
    });
  });

  // =========================================================================
  group('El portón, con su cliente HTTP de verdad', () {
    /// Lo que el servidor contesta a cada ruta.
    ///
    /// Se escribe aquí y no en una capa falsa porque lo que se prueba es justamente el
    /// ENCADENADO: `/companies` vacío → `/organizations` → `/membership`. Con un
    /// repositorio de mentira, el paso que importa —de dónde sale el id de la
    /// organización— se daría por hecho.
    MockClient servidor({
      required String organizaciones,
      required int estadoDeOrganizaciones,
      required String membresia,
      required int estadoDeMembresia,
    }) => MockClient((peticion) async {
      final ruta = peticion.url.path;

      if (ruta.endsWith('/auth/login')) {
        return http.Response(
          '''
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
          ''',
          200,
          headers: const {'content-type': 'application/json'},
        );
      }

      // CERO EMPRESAS: es el estado en el que E3 aparece, y el que tenía el ensayo.
      if (ruta.endsWith('/companies')) {
        return http.Response(
          '[]',
          200,
          headers: const {'content-type': 'application/json'},
        );
      }

      if (ruta.endsWith('/organizations')) {
        return http.Response(
          organizaciones,
          estadoDeOrganizaciones,
          headers: const {'content-type': 'application/json'},
        );
      }

      if (ruta.endsWith('/membership')) {
        return http.Response(
          membresia,
          estadoDeMembresia,
          headers: const {'content-type': 'application/json'},
        );
      }

      return http.Response('{}', 404);
    });

    const unaOrganizacion =
        '[{"id": "$_orgA", "name": "Cliente de Prueba", "status": "activa", '
        '"createdAt": "2026-10-01T12:00:00Z"}]';

    Future<({GestorDeSesion sesion, GestorDeCompany company})> montarPorton(
      WidgetTester tester,
      MockClient cliente,
    ) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final desnudo = ApiClient(
        config: ApiConfig.resolve(raw: 'http://localhost:5199').when(
          ok: (c) => c,
          failure: (f) => throw StateError(f.message),
        ),
        cliente: cliente,
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

      // D-56 · UN SOLO GUARDIA PARA LOS DOS, como en el arranque: el portón se lo reparte
      // a las pantallas y el `onExit` del router le pregunta. Dos serían dos respuestas
      // distintas a la misma pregunta. Aquí no hay ningún formulario montado, así que
      // responde «no hay nada que perder» y ninguna navegación pregunta.
      final guardia = GuardiaDeSalida();

      // EL PORTÓN VA DENTRO DEL ROUTER, igual que en el arranque de verdad: desde C1 lee
      // la dirección para saber qué apartado y qué pestaña se están viendo, y fuera de un
      // router eso lanza. Montarlo con `home:` probaría un montaje que no existe.
      await tester.pumpWidget(
        MaterialApp.router(
          theme: MarcaSeventra.tema(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: construirRouterWeb(
            guardia: guardia,
            porton: PortonWeb(
              guardia: guardia,
              gestorDeSesion: sesion,
              gestorDeCompany: company,
              repositorioDeLogotipos: LogotipoRepositorioHttp(autenticado),
              repositorioDeAreas: AreasRepositorioHttp(autenticado),
              repositorioDeEmpresas: EmpresasRepositorioHttp(autenticado),
              repositorioDeExpedientes: ExpedientesRepositorioHttp(autenticado),
              repositorioDePuestos: PuestosRepositorioHttp(autenticado),
              repositorioDeSucursales: SucursalesRepositorioHttp(autenticado),
              repositorioDeUsuarios: UsuariosRepositorioHttp(autenticado),
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
          ),
        ),
      );

      // EL ORDEN ES EL DE VERDAD, y por eso el login va DESPUÉS de montar: el portón
      // arranca pidiendo restaurar la sesión, no encuentra credencial guardada y enseña
      // el login. Iniciar sesión antes de montarlo haría que `restaurar()` publicara
      // `NoAutenticado` encima y la prueba acabaría mirando la pantalla de login —que es
      // exactamente lo que pasó al escribir esto—.
      //
      // Y además es lo único que deja ver el saludo: `/auth/refresh` responde SIN
      // `displayName`, así que una sesión restaurada no tiene nombre con el que saludar.
      await tester.pump();

      final entrada = await sesion.iniciarSesion(
        email: 'prueba@ejemplo.mx',
        password: 'Contrasena-de-prueba-1',
      );

      entrada.when(
        ok: (_) {},
        failure: (f) => throw StateError('el login de prueba falló: ${f.message}'),
      );

      // SIN `pumpAndSettle`, y no es pereza: mientras se averigua, el portón enseña su
      // espera con un `CircularProgressIndicator`, que es una animación infinita y hace
      // que `pumpAndSettle` agote el tiempo. Se avanza cuadro a cuadro, que es lo que
      // deja correr las tres lecturas encadenadas.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      return (sesion: sesion, company: company);
    }

    testWidgets('al OWNER sin empresas le ofrece crear la primera', (tester) async {
      // EL OWNER LLEGA CON LA LISTA DE PERMISOS VACÍA, y eso no es un error: su
      // autoridad es del rol y el backend no le materializa filas. Si la pantalla
      // mirara la lista antes del rol, el Owner —la única persona que puede usar esto—
      // se quedaría fuera.
      await montarPorton(
        tester,
        servidor(
          organizaciones: unaOrganizacion,
          estadoDeOrganizaciones: 200,
          membresia:
              '{"identityId": "0193f0a0-0000-7000-8000-000000000001", '
              '"role": "owner", "permissions": []}',
          estadoDeMembresia: 200,
        ),
      );

      expect(find.text('Crea tu primera empresa'), findsOneWidget);
      expect(find.text('Todavía no tienes ninguna empresa'), findsNothing);

      // Y EL SALUDO SALE DE LA SESIÓN, con el nombre que mandó el servidor.
      expect(find.text('Hola, Usuario de prueba'), findsOneWidget);
    });

    testWidgets('a un ADMIN con `companies.manage` también', (tester) async {
      await montarPorton(
        tester,
        servidor(
          organizaciones: unaOrganizacion,
          estadoDeOrganizaciones: 200,
          membresia:
              '{"identityId": "0193f0a0-0000-7000-8000-000000000001", '
              '"role": "admin", "permissions": ["companies.manage"]}',
          estadoDeMembresia: 200,
        ),
      );

      expect(find.text('Crea tu primera empresa'), findsOneWidget);
    });

    testWidgets('a un ADMIN SIN el permiso le sale el mensaje de siempre', (
      tester,
    ) async {
      // ⚠️ LA FRONTERA DE LA ETAPA. El botón es la excepción; esto es el caso general,
      // y el mensaje tiene que seguir siendo exactamente el de antes.
      await montarPorton(
        tester,
        servidor(
          organizaciones: unaOrganizacion,
          estadoDeOrganizaciones: 200,
          membresia:
              '{"identityId": "0193f0a0-0000-7000-8000-000000000001", '
              '"role": "admin", "permissions": []}',
          estadoDeMembresia: 200,
        ),
      );

      expect(find.text('Todavía no tienes ninguna empresa'), findsOneWidget);
      expect(find.text('Crea tu primera empresa'), findsNothing);
      expect(find.text('Volver a intentar'), findsNothing);
    });

    testWidgets('a quien NO es miembro —404— también', (tester) async {
      // Un Maestro de una empresa de otra organización, o una cuenta recién invitada.
      // Un 404 de membresía NO es un fallo: es «no eres miembro».
      await montarPorton(
        tester,
        servidor(
          organizaciones: unaOrganizacion,
          estadoDeOrganizaciones: 200,
          membresia: '{"code": "organizacion_no_disponible", "message": "No disponible."}',
          estadoDeMembresia: 404,
        ),
      );

      expect(find.text('Todavía no tienes ninguna empresa'), findsOneWidget);
      expect(find.text('Crea tu primera empresa'), findsNothing);
    });

    testWidgets('sin ninguna organización, el mensaje de siempre', (tester) async {
      await montarPorton(
        tester,
        servidor(
          organizaciones: '[]',
          estadoDeOrganizaciones: 200,
          membresia: '{}',
          estadoDeMembresia: 404,
        ),
      );

      expect(find.text('Todavía no tienes ninguna empresa'), findsOneWidget);
      expect(find.text('Crea tu primera empresa'), findsNothing);
    });

    testWidgets('si la lectura FALLA, ofrece reintentar y NO dice que no puedas', (
      tester,
    ) async {
      // ⚠️ AUSENCIA NUNCA ES CERO. Un 500 en la lista de organizaciones no significa
      // «no tienes autoridad»: significa que no se pudo preguntar. Enseñar el mensaje
      // seco dejaría a un cliente que acaba de contratar sin ninguna salida, con la
      // pantalla diciéndole algo falso.
      await montarPorton(
        tester,
        servidor(
          organizaciones: '{"code": "error", "message": "Algo falló."}',
          estadoDeOrganizaciones: 500,
          membresia: '{}',
          estadoDeMembresia: 200,
        ),
      );

      expect(find.text('Todavía no tienes ninguna empresa'), findsOneWidget);
      expect(find.text('Volver a intentar'), findsOneWidget);
      expect(find.text('Crea tu primera empresa'), findsNothing);
    });

    testWidgets('al VOLVER LA PESTAÑA AL FRENTE, el contexto se pone al día', (
      tester,
    ) async {
      // P2 · LA MITAD QUE NO DEPENDE DE QUE ALGUIEN PULSE NADA. El caso real es que a
      // alguien le retiren un permiso mientras está en otra ventana: al volver, lo
      // primero que hace es mirar la pantalla, y es el único instante en el que una
      // lectura de más vale la pena.
      //
      // La otra mitad —reaccionar a un 403— la cubre `vigilante_de_contexto_test`.
      var contextos = 0;

      final cliente = MockClient((peticion) async {
        final ruta = peticion.url.path;

        if (ruta.endsWith('/auth/login')) {
          return http.Response(
            '''
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
            ''',
            200,
            headers: const {'content-type': 'application/json'},
          );
        }

        if (ruta.endsWith('/context')) {
          contextos++;

          return http.Response(
            '{"companyId": "$_idUnica", '
            '"organizationId": "$_orgA", "companyName": "RISEG", '
            '"companyStatus": "activa", "organizationName": "Cliente de Prueba", '
            '"role": "maestro", "isMaestro": true, "enabledModules": [], '
            '"effectivePermissions": [], "restricted": false}',
            200,
            headers: const {'content-type': 'application/json'},
          );
        }

        // UNA SOLA EMPRESA: así se entra directo y queda una activa, que es el único
        // estado en el que ponerse al día significa algo.
        if (ruta.endsWith('/companies')) {
          return http.Response(
            '[{"companyId": "$_idUnica", "organizationId": "$_orgA", '
            '"companyName": "RISEG", "organizationName": "Cliente de Prueba", '
            '"role": "maestro", "status": "activa", "legalName": null}]',
            200,
            headers: const {'content-type': 'application/json'},
          );
        }

        return http.Response('[]', 200);
      });

      await montarPorton(tester, cliente);

      // Lo que leyó al entrar no cuenta: lo que se mide es el regreso.
      final alEntrar = contextos;
      expect(alEntrar, greaterThan(0), reason: 'al entrar se lee el contexto');

      // SE SALE Y SE VUELVE, por los estados reales del ciclo de vida.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(
        contextos,
        greaterThan(alEntrar),
        reason: 'volver al frente tiene que pedir el contexto otra vez',
      );
    });

    testWidgets('al CERRAR SESIÓN, una averiguación en vuelo no se publica', (
      tester,
    ) async {
      // ⚠️ ES UN CANDADO CONTRA UNA FUGA ENTRE CUENTAS. Si alguien cierra sesión
      // mientras las lecturas están en vuelo, la respuesta llega después: sin el
      // contador de generación, la cuenta siguiente vería las organizaciones de la
      // anterior. No es una carrera teórica —la pantalla hace TRES lecturas
      // encadenadas— y lo que se filtraría son nombres de clientes.
      final completar = Completer<http.Response>();
      var lecturasDeOrganizaciones = 0;

      final cliente = MockClient((peticion) async {
        final ruta = peticion.url.path;

        if (ruta.endsWith('/auth/login')) {
          return http.Response(
            '''
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
            ''',
            200,
            headers: const {'content-type': 'application/json'},
          );
        }

        if (ruta.endsWith('/companies')) {
          return http.Response(
            '[]',
            200,
            headers: const {'content-type': 'application/json'},
          );
        }

        // LA PRIMERA LECTURA SE QUEDA COLGADA a propósito: así se puede cerrar la
        // sesión con ella en vuelo, que es justo el instante que esto defiende. La
        // SEGUNDA —la de la cuenta que entra después— contesta en el acto, y contesta
        // que esa cuenta no administra ninguna organización.
        if (ruta.endsWith('/organizations')) {
          lecturasDeOrganizaciones++;

          return lecturasDeOrganizaciones == 1
              ? completar.future
              : http.Response(
                  '[]',
                  200,
                  headers: const {'content-type': 'application/json'},
                );
        }

        // Y LA MEMBRESÍA CONTESTA «owner», porque si no esta prueba no probaría nada:
        // sin ella la averiguación tardía terminaría en «no tienes autoridad» por su
        // cuenta y pasaría con candado o sin él. Se comprobó quitando los dos candados
        // y viendo la prueba FALLAR.
        if (ruta.endsWith('/membership')) {
          return http.Response(
            '{"identityId": "0193f0a0-0000-7000-8000-000000000001", '
            '"role": "owner", "permissions": []}',
            200,
            headers: const {'content-type': 'application/json'},
          );
        }

        if (ruta.endsWith('/auth/logout')) return http.Response('', 204);

        return http.Response('{}', 404);
      });

      final gestores = await montarPorton(tester, cliente);

      // Está esperando: ni el mensaje ni el formulario, porque todavía no se sabe.
      expect(find.text('Crea tu primera empresa'), findsNothing);

      await gestores.sesion.cerrarSesion();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      // ENTRA LA SEGUNDA CUENTA. Es lo que hace real a esta prueba: con la sesión
      // cerrada y nada más, el portón enseña el login y no habría nada de E3 que
      // pudiera filtrarse. La fuga sólo se ve cuando alguien ya está dentro.
      final segunda = await gestores.sesion.iniciarSesion(
        email: 'otra@ejemplo.mx',
        password: 'Contrasena-de-prueba-1',
      );

      segunda.when(
        ok: (_) {},
        failure: (f) => throw StateError('el segundo login falló: ${f.message}'),
      );

      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      // La segunda cuenta no administra nada: le toca el mensaje de siempre.
      expect(find.text('Todavía no tienes ninguna empresa'), findsOneWidget);

      // Y AHORA CONTESTA LA LECTURA DE LA PRIMERA, tarde, con una organización donde
      // aquella persona SÍ era Owner. Si se publicara, la segunda cuenta vería el
      // nombre de un cliente que no es suyo y un botón que no le toca.
      completar.complete(
        http.Response(
          unaOrganizacion,
          200,
          headers: const {'content-type': 'application/json'},
        ),
      );

      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(find.text('Todavía no tienes ninguna empresa'), findsOneWidget);
      expect(find.text('Crea tu primera empresa'), findsNothing);
      expect(find.text('Cliente de Prueba'), findsNothing);
    });

    testWidgets('y si falla la MEMBRESÍA, lo mismo: reintentar', (tester) async {
      // Un fallo parcial tampoco se aprovecha: una lista de destinos a la que le falte
      // uno es peor que no tener lista, porque de ahí sale dónde NACE una empresa.
      await montarPorton(
        tester,
        servidor(
          organizaciones: unaOrganizacion,
          estadoDeOrganizaciones: 200,
          membresia: '{"code": "error", "message": "Algo falló."}',
          estadoDeMembresia: 500,
        ),
      );

      expect(find.text('Volver a intentar'), findsOneWidget);
      expect(find.text('Crea tu primera empresa'), findsNothing);
    });
  });
}

/// Sin credencial guardada: el portón arranca sin sesión y la prueba la abre por el
/// camino real.
class _SinSesion implements AlmacenSesionRemota {
  @override
  Future<CredencialRemota?> leer() async => null;

  @override
  Future<void> escribir(CredencialRemota credencial) async {}

  @override
  Future<void> borrar() async {}
}

/// Sin empresa recordada. Con cero empresas no hay nada que recordar, y una preferencia
/// de otra sesión no debe decidir nada aquí.
class _SinPreferencia implements AlmacenCompanyRecordada {
  const _SinPreferencia();

  @override
  Future<String?> leer() async => null;

  @override
  Future<void> escribir(String companyId) async {}

  @override
  Future<void> borrar() async {}
}
