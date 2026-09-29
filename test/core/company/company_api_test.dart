// Integration Foundation IF-3 — las dos llamadas de Company.
//
// La pila es real de arriba abajo menos el transporte: `CompanyApi` habla con el
// `ApiClientAutenticado` de IF-2, que pide el token a un `GestorDeSesion` de verdad,
// que se autenticó contra el mismo `MockClient`. Así, afirmar sobre la petición que
// llega al transporte es afirmar sobre lo que saldría por el cable, incluido el
// `Authorization` que esta capa nunca escribe a mano.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/api/api_client_autenticado.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/auth_api.dart';
import 'package:riseg_one/core/auth/gestor_de_sesion.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/company/company_api.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/core/logging/app_logger.dart';

class _AlmacenSesionEnMemoria implements AlmacenSesionRemota {
  CredencialRemota? guardada;

  @override
  Future<CredencialRemota?> leer() async => guardada;

  @override
  Future<void> escribir(CredencialRemota credencial) async =>
      guardada = credencial;

  @override
  Future<void> borrar() async => guardada = null;
}

void main() {
  final config = ApiConfig.resolve(
    raw: 'http://localhost:5199',
  ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

  final t0 = DateTime.utc(2026, 9, 28, 12);

  const companyUno = '0193f0a0-0000-7000-8000-000000000001';
  const companyDos = '0193f0a0-0000-7000-8000-000000000002';
  const organizationId = '0193f0a0-0000-7000-8000-0000000000ff';

  String cuerpoDeSesion() => jsonEncode({
    'accessToken': 'at_1',
    'accessExpiresAt': t0.add(const Duration(minutes: 30)).toIso8601String(),
    'refreshToken': 'rt_1',
    'refreshExpiresAt': t0.add(const Duration(days: 14)).toIso8601String(),
    'sessionId': '0193f0a0-0000-7000-8000-00000000aaaa',
    'displayName': 'Ana Torres',
    'email': 'ana@seventra.mx',
  });

  Map<String, Object?> companyJson(
    String id,
    String nombre, {
    String organizacion = 'Grupo RISEG',
    String role = 'maestro',
  }) => {
    'companyId': id,
    'organizationId': organizationId,
    'companyName': nombre,
    'organizationName': organizacion,
    'role': role,
  };

  Map<String, Object?> contextoJson(String id) => {
    'companyId': id,
    'organizationId': organizationId,
    'companyName': 'Seguridad RISEG',
    'companyStatus': 'activa',
    'organizationName': 'Grupo RISEG',
    'role': 'maestro',
    'isMaestro': true,
    'enabledModules': ['personal', 'clients_services'],
    'effectivePermissions': ['personal.read', 'personal.manage'],
    'restricted': false,
  };

  Future<({CompanyApi api, List<http.Request> vistas})> construir(
    Future<http.Response> Function(http.Request) responder, {
    Duration? timeoutDelCliente,
  }) async {
    final vistas = <http.Request>[];

    final desnudo = ApiClient(
      config: config,
      cliente: MockClient((peticion) async {
        vistas.add(peticion);

        if (peticion.url.path.endsWith('/auth/login')) {
          return http.Response(cuerpoDeSesion(), 200);
        }

        return responder(peticion);
      }),
      logger: AppLogger.console(),
      timeout: timeoutDelCliente ?? ApiClient.timeoutPorOmision,
    );

    final sesion = GestorDeSesion(
      api: AuthApi(desnudo),
      almacen: _AlmacenSesionEnMemoria(),
      logger: AppLogger.console(),
      ahora: () => t0,
    );

    addTearDown(sesion.dispose);

    await sesion.iniciarSesion(email: 'ana@seventra.mx', password: 'x');
    vistas.clear();

    return (
      api: CompanyApi(ApiClientAutenticado(cliente: desnudo, gestor: sesion)),
      vistas: vistas,
    );
  }

  T exigirOk<T>(Result<T> resultado) => resultado.when(
    ok: (valor) => valor,
    failure: (f) => fail('Se esperaba un valor y llegó: ${f.message}'),
  );

  Failure exigirFallo(Result<Object?> resultado) => resultado.when(
    ok: (_) => fail('Se esperaba un fallo y la llamada salió bien'),
    failure: (failure) => failure,
  );

  group('Descubrimiento — GET /companies', () {
    test('va a /api/v1/companies, firmado y sin Company en la ruta', () async {
      final armado = await construir(
        (_) async => http.Response(jsonEncode([]), 200),
      );

      await armado.api.listarAccesibles();

      final peticion = armado.vistas.single;

      expect(peticion.method, 'GET');
      expect(peticion.url.path, '/api/v1/companies');
      expect(peticion.headers['Authorization'], 'Bearer at_1');
    });

    test('lee una lista de una empresa', () async {
      final armado = await construir(
        (_) async => http.Response(
          jsonEncode([companyJson(companyUno, 'Seguridad RISEG')]),
          200,
        ),
      );

      final lista = exigirOk(await armado.api.listarAccesibles());

      expect(lista, hasLength(1));
      expect(lista.single.companyId, companyUno);
      expect(lista.single.role, 'maestro');
    });

    test('CONSERVA el orden del servidor, no reordena', () async {
      // El backend ordena por `organization.name, company.name`. Reordenar aquí
      // duplicaría una decisión ya tomada y podría divergir de ella.
      final armado = await construir(
        (_) async => http.Response(
          jsonEncode([
            companyJson(companyUno, 'Zeta', organizacion: 'Alfa'),
            companyJson(companyDos, 'Alfa', organizacion: 'Beta'),
          ]),
          200,
        ),
      );

      final lista = exigirOk(await armado.api.listarAccesibles());

      expect(lista.map((c) => c.companyName).toList(), ['Zeta', 'Alfa']);
    });

    test(
      'empresas de DOS Organizations llegan en una sola respuesta',
      () async {
        // Es lo que hace que no haga falta un selector de Organization: el
        // descubrimiento sale de `company_access` y no filtra por Organization.
        final armado = await construir(
          (_) async => http.Response(
            jsonEncode([
              companyJson(companyUno, 'Uno', organizacion: 'Grupo A'),
              companyJson(companyDos, 'Dos', organizacion: 'Grupo B'),
            ]),
            200,
          ),
        );

        final lista = exigirOk(await armado.api.listarAccesibles());

        expect(lista.map((c) => c.organizationName).toSet(), {
          'Grupo A',
          'Grupo B',
        });
      },
    );

    test('una lista vacía es una respuesta válida, no un fallo', () async {
      final armado = await construir(
        (_) async => http.Response(jsonEncode([]), 200),
      );

      expect(exigirOk(await armado.api.listarAccesibles()), isEmpty);
    });

    test('una empresa ilegible invalida la lista entera', () async {
      // Seguir con las que sí se entendieron dejaría al usuario eligiendo entre un
      // subconjunto silencioso de sus empresas.
      final armado = await construir(
        (_) async => http.Response(
          jsonEncode([
            companyJson(companyUno, 'Uno'),
            {'companyId': companyDos},
          ]),
          200,
        ),
      );

      expect(
        exigirFallo(await armado.api.listarAccesibles()),
        isA<ApiRespuestaInesperadaFailure>(),
      );
    });

    test('un objeto donde iba una lista es desacuerdo de contrato', () async {
      final armado = await construir(
        (_) async => http.Response('{"items":[]}', 200),
      );

      expect(
        exigirFallo(await armado.api.listarAccesibles()),
        isA<ApiRespuestaInesperadaFailure>(),
      );
    });

    test('HTML de un proxy no deja escapar FormatException', () async {
      final armado = await construir(
        (_) async => http.Response('<html>proxy</html>', 200),
      );

      expect(
        exigirFallo(await armado.api.listarAccesibles()),
        isA<ApiJsonInvalidoFailure>(),
      );
    });

    test('sin red llega como fallo de transporte', () async {
      final armado = await construir(
        (_) async => throw http.ClientException('sin red'),
      );

      expect(
        exigirFallo(await armado.api.listarAccesibles()),
        isA<ApiSinConexionFailure>(),
      );
    });
  });

  group('Contexto — GET /companies/{id}/context', () {
    test('la ruta lleva EXACTAMENTE ese companyId', () async {
      final armado = await construir(
        (_) async => http.Response(jsonEncode(contextoJson(companyDos)), 200),
      );

      await armado.api.contexto(companyDos);

      expect(
        armado.vistas.single.url.path,
        '/api/v1/companies/$companyDos/context',
      );
      expect(armado.vistas.single.url.path, isNot(contains(companyUno)));
    });

    test('parsea los diez campos', () async {
      final armado = await construir(
        (_) async => http.Response(jsonEncode(contextoJson(companyUno)), 200),
      );

      final contexto = exigirOk(await armado.api.contexto(companyUno));

      expect(contexto.companyId, companyUno);
      expect(contexto.organizationId, organizationId);
      expect(contexto.companyName, 'Seguridad RISEG');
      expect(contexto.companyStatus, 'activa');
      expect(contexto.organizationName, 'Grupo RISEG');
      expect(contexto.role, 'maestro');
      expect(contexto.isMaestro, isTrue);
      expect(contexto.restricted, isFalse);
      expect(contexto.enabledModules, isNotEmpty);
      expect(contexto.effectivePermissions, isNotEmpty);
    });

    test('un companyId mal formado NO llega a salir', () async {
      final armado = await construir((_) async => http.Response('{}', 200));

      expect(
        exigirFallo(await armado.api.contexto('empresa-uno')),
        isA<ApiConfigFailure>(),
      );
      expect(
        armado.vistas,
        isEmpty,
        reason: 'un id inválido es un error de programación, no un viaje',
      );
    });

    test('404 empresa_no_disponible conserva status y código', () async {
      final armado = await construir(
        (_) async => http.Response(
          '{"code":"empresa_no_disponible","message":"La empresa no existe o no tienes acceso a ella."}',
          404,
        ),
      );

      final fallo = exigirFallo(await armado.api.contexto(companyUno));

      expect((fallo as ApiHttpFailure).statusCode, 404);
      expect(fallo.codigo, 'empresa_no_disponible');
      expect(
        CompanyApi.esEmpresaNoDisponible(fallo),
        isTrue,
        reason: 'es el 404 AUTORITATIVO',
      );
    });

    test('un 404 sin ese código NO es autoritativo', () async {
      // Un 404 de un proxy, o de una ruta que no existe, no dice nada sobre el
      // acceso a la empresa. Exigir status Y código evita cerrar una empresa por un
      // error ajeno.
      final armado = await construir(
        (_) async => http.Response('<html>Not Found</html>', 404),
      );

      final fallo = exigirFallo(await armado.api.contexto(companyUno));

      expect(CompanyApi.esEmpresaNoDisponible(fallo), isFalse);
    });

    test('402 subscription_restricted se reconoce y NO es revocación', () async {
      final armado = await construir(
        (_) async => http.Response(
          '{"code":"subscription_restricted","message":"La suscripción de la organización no permite la operación normal."}',
          402,
        ),
      );

      final fallo = exigirFallo(await armado.api.contexto(companyUno));

      expect((fallo as ApiHttpFailure).statusCode, 402);
      expect(fallo.codigo, 'subscription_restricted');
      expect(CompanyApi.esSuscripcionRestringida(fallo), isTrue);
      expect(
        CompanyApi.esEmpresaNoDisponible(fallo),
        isFalse,
        reason: 'una restricción comercial no es una revocación de acceso',
      );
    });

    test('un contexto incompleto se rechaza nombrando el campo', () async {
      final armado = await construir(
        (_) async => http.Response(
          jsonEncode(contextoJson(companyUno)..remove('enabledModules')),
          200,
        ),
      );

      expect(
        exigirFallo(await armado.api.contexto(companyUno)).message,
        contains('enabledModules'),
      );
    });

    test('tiempo agotado llega como tal, sin disfrazarse de 404', () async {
      // El plazo general del cliente se pone en 1 ms. El login sobrevive porque
      // impone el suyo de 30 s (verificado en IF-2), así que lo que se corta es
      // exactamente la llamada de contexto.
      final armado = await construir((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return http.Response(jsonEncode(contextoJson(companyUno)), 200);
      }, timeoutDelCliente: const Duration(milliseconds: 1));

      final fallo = exigirFallo(await armado.api.contexto(companyUno));

      expect(fallo, isA<ApiTimeoutFailure>());
      expect(
        CompanyApi.esEmpresaNoDisponible(fallo),
        isFalse,
        reason: 'un plazo agotado no dice nada sobre el acceso',
      );
    });
  });

  test('Ningún encabezado de empresa: la Company va en la ruta', () async {
    final armado = await construir(
      (_) async => http.Response(jsonEncode(contextoJson(companyUno)), 200),
    );

    await armado.api.contexto(companyUno);

    final encabezados =
        armado.vistas.single.headers.keys.map((k) => k.toLowerCase()).toList();

    expect(encabezados, isNot(contains('x-company-id')));
    expect(encabezados, isNot(contains('company')));
    expect(encabezados, isNot(contains('x-company')));
    expect(armado.vistas.single.url.path, contains(companyUno));
  });
}
