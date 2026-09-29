// Integration Foundation IF-2 — el cliente HTTP con sesión.
//
// Toda la pila es real menos el transporte: el decorador pide el token a un
// `GestorDeSesion` de verdad, que refresca contra el mismo `MockClient`. Contar
// las peticiones que llegan al transporte es por tanto una afirmación sobre lo que
// de verdad saldría por el cable.
//
// LAS DOS COSAS QUE ESTE ARCHIVO PROTEGE:
//
//  · el reintento ocurre **exactamente una vez**. Insistir pediría un canje de
//    refresco tras otro, y el backend responde a la reutilización revocando la
//    sesión completa;
//  · el decorador **no interpreta** el 402 ni el 403. Esas son preguntas de
//    autorización —suscripción restringida, permiso ausente, módulo apagado— con
//    respuestas que dependen del módulo; decidirlas aquí las esconderia en el
//    transporte, que es justo el error que IF-1 evitó.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/api/api_client_autenticado.dart';
import 'package:riseg_one/core/api/api_respuesta.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/auth_api.dart';
import 'package:riseg_one/core/auth/gestor_de_sesion.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/core/logging/app_logger.dart';

class _AlmacenEnMemoria implements AlmacenSesionRemota {
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

  String cuerpoDeSesion({
    required String accessToken,
    required String refreshToken,
    Duration accesoDura = const Duration(minutes: 30),
  }) => jsonEncode({
    'accessToken': accessToken,
    'accessExpiresAt': t0.add(accesoDura).toIso8601String(),
    'refreshToken': refreshToken,
    'refreshExpiresAt': t0.add(const Duration(days: 14)).toIso8601String(),
    'identityId': '0193f0a0-0000-7000-8000-00000000cafe',
    'sessionId': '0193f0a0-0000-7000-8000-000000000001',
    'displayName': 'Ana Torres',
    'email': 'ana@seventra.mx',
  });

  ({
    ApiClientAutenticado cliente,
    GestorDeSesion gestor,
    List<http.Request> vistas,
  })
  construir(Future<http.Response> Function(http.Request) responder) {
    final vistas = <http.Request>[];

    final desnudo = ApiClient(
      config: config,
      cliente: MockClient((peticion) async {
        vistas.add(peticion);
        return responder(peticion);
      }),
      logger: AppLogger.console(),
    );

    final gestor = GestorDeSesion(
      api: AuthApi(desnudo),
      almacen: _AlmacenEnMemoria(),
      logger: AppLogger.console(),
      ahora: () => t0,
    );

    addTearDown(gestor.dispose);

    return (
      cliente: ApiClientAutenticado(cliente: desnudo, gestor: gestor),
      gestor: gestor,
      vistas: vistas,
    );
  }

  /// Las peticiones de negocio, sin las de autenticación.
  List<http.Request> deNegocio(List<http.Request> vistas) =>
      vistas.where((p) => !p.url.path.contains('/auth/')).toList();

  ApiRespuesta exigirRespuesta(Result<ApiRespuesta> resultado) =>
      resultado.when(
        ok: (respuesta) => respuesta,
        failure: (f) => fail('Se esperaba una respuesta y llegó: ${f.message}'),
      );

  Failure exigirFallo(Result<ApiRespuesta> resultado) => resultado.when(
    ok: (r) => fail('Se esperaba un fallo y llegó HTTP ${r.statusCode}'),
    failure: (failure) => failure,
  );

  group('La firma', () {
    test('los cinco verbos llevan Bearer', () async {
      for (final invocar
          in <Future<Result<ApiRespuesta>> Function(ApiClientAutenticado)>[
            (c) => c.get('/companies'),
            (c) => c.post('/companies', json: {'name': 'X'}),
            (c) => c.put('/companies/1', json: {'name': 'X'}),
            (c) => c.patch('/companies/1', json: {'name': 'X'}),
            (c) => c.delete('/companies/1'),
          ]) {
        final armado = construir(
          (peticion) async =>
              peticion.url.path.endsWith('/auth/login')
                  ? http.Response(
                    cuerpoDeSesion(accessToken: 'at_1', refreshToken: 'rt_1'),
                    200,
                  )
                  : http.Response('{}', 200),
        );

        await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');
        await invocar(armado.cliente);

        expect(
          deNegocio(armado.vistas).single.headers['Authorization'],
          'Bearer at_1',
        );
      }
    });

    test('la sesión manda sobre un Authorization del llamante', () async {
      // Quién firma lo decide el gestor, no la capa que pide un recurso.
      final armado = construir(
        (peticion) async =>
            peticion.url.path.endsWith('/auth/login')
                ? http.Response(
                  cuerpoDeSesion(accessToken: 'at_1', refreshToken: 'rt_1'),
                  200,
                )
                : http.Response('{}', 200),
      );

      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');
      await armado.cliente.get(
        '/companies',
        headers: {'Authorization': 'Bearer inventado', 'X-Otro': 'se conserva'},
      );

      final peticion = deNegocio(armado.vistas).single;

      expect(peticion.headers['Authorization'], 'Bearer at_1');
      expect(peticion.headers['X-Otro'], 'se conserva');
    });

    test('sin sesión NO se envía nada', () async {
      final armado = construir((_) async => http.Response('{}', 200));

      final fallo = exigirFallo(await armado.cliente.get('/companies'));

      expect(fallo, isA<ApiSinSesionFailure>());
      expect(
        armado.vistas,
        isEmpty,
        reason:
            'mandar la petición sin firma sólo para cosechar el 401 gasta '
            'un viaje y cuota del limitador',
      );
    });

    test(
      'un acceso por caducar se refresca ANTES de enviar la petición',
      () async {
        final armado = construir((peticion) async {
          if (peticion.url.path.endsWith('/auth/login')) {
            return http.Response(
              cuerpoDeSesion(
                accessToken: 'at_1',
                refreshToken: 'rt_1',
                accesoDura: const Duration(seconds: 10),
              ),
              200,
            );
          }

          if (peticion.url.path.endsWith('/auth/refresh')) {
            return http.Response(
              cuerpoDeSesion(accessToken: 'at_2', refreshToken: 'rt_2'),
              200,
            );
          }

          return http.Response('{}', 200);
        });

        await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');
        await armado.cliente.get('/companies');

        expect(
          deNegocio(armado.vistas).single.headers['Authorization'],
          'Bearer at_2',
          reason: 'la petición no llega a recibir un 401',
        );
        expect(deNegocio(armado.vistas), hasLength(1));
      },
    );
  });

  group('El 401 y el reintento', () {
    /// Un servidor que responde 401 las primeras [cuantos401] veces que le piden
    /// un recurso de negocio, y 200 después.
    ({
      ApiClientAutenticado cliente,
      GestorDeSesion gestor,
      List<http.Request> vistas,
    })
    servidorQueRechaza({
      required int cuantos401,
      bool refrescoFunciona = true,
    }) {
      var rechazos = 0;
      var numero = 1;

      return construir((peticion) async {
        if (peticion.url.path.endsWith('/auth/login')) {
          return http.Response(
            cuerpoDeSesion(accessToken: 'at_1', refreshToken: 'rt_1'),
            200,
          );
        }

        if (peticion.url.path.endsWith('/auth/refresh')) {
          if (!refrescoFunciona) {
            return http.Response('{"code":"refresh_reutilizado"}', 401);
          }

          numero++;
          return http.Response(
            cuerpoDeSesion(
              accessToken: 'at_$numero',
              refreshToken: 'rt_$numero',
            ),
            200,
          );
        }

        if (rechazos < cuantos401) {
          rechazos++;
          return http.Response('{"code":"sesion_invalida"}', 401);
        }

        return http.Response('{"ok":true}', 200);
      });
    }

    test(
      'un 401 se refresca y se reintenta UNA vez, con el token nuevo',
      () async {
        final armado = servidorQueRechaza(cuantos401: 1);
        await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');

        final respuesta = exigirRespuesta(
          await armado.cliente.get('/companies'),
        );

        expect(respuesta.statusCode, 200);

        final negocio = deNegocio(armado.vistas);

        expect(
          negocio,
          hasLength(2),
          reason: 'el original y un solo reintento',
        );
        expect(negocio.first.headers['Authorization'], 'Bearer at_1');
        expect(negocio.last.headers['Authorization'], 'Bearer at_2');
      },
    );

    test('un segundo 401 DETIENE el intento: no hay tercera', () async {
      final armado = servidorQueRechaza(cuantos401: 99);
      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');

      final respuesta = exigirRespuesta(await armado.cliente.get('/companies'));

      expect(respuesta.statusCode, 401);
      expect(deNegocio(armado.vistas), hasLength(2));
      expect(
        armado.vistas.where((p) => p.url.path.endsWith('/auth/refresh')),
        hasLength(1),
        reason:
            'un canje tras otro es lo que el backend lee como reutilización',
      );
    });

    test(
      'si el refresco falla, se devuelve el 401 original como respuesta',
      () async {
        // El contrato heredado de `ApiClient` es «hubo respuesta → hay respuesta».
        // El estado de la sesión ya refleja lo que pasó.
        final armado = servidorQueRechaza(
          cuantos401: 99,
          refrescoFunciona: false,
        );
        await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');

        final respuesta = exigirRespuesta(
          await armado.cliente.get('/companies'),
        );

        expect(respuesta.statusCode, 401);
        expect(
          deNegocio(armado.vistas),
          hasLength(1),
          reason: 'no se reintentó',
        );
        expect(armado.gestor.estado, isA<NoAutenticado>());
      },
    );

    test('el reintento conserva el método y el cuerpo', () async {
      final armado = servidorQueRechaza(cuantos401: 1);
      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');

      await armado.cliente.post('/clients', json: {'name': 'Cliente Uno'});

      final negocio = deNegocio(armado.vistas);

      expect(negocio, hasLength(2));
      for (final peticion in negocio) {
        expect(peticion.method, 'POST');
        expect(jsonDecode(peticion.body), {'name': 'Cliente Uno'});
      }
    });

    test('el reintento conserva la consulta', () async {
      final armado = servidorQueRechaza(cuantos401: 1);
      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');

      await armado.cliente.get('/employees', query: {'query': 'Juan Pérez'});

      for (final peticion in deNegocio(armado.vistas)) {
        expect(peticion.url.queryParameters['query'], 'Juan Pérez');
      }
    });
  });

  group('Lo que NO interpreta', () {
    Future<ApiRespuesta> pedirCon(int status, String cuerpo) async {
      final armado = construir(
        (peticion) async =>
            peticion.url.path.endsWith('/auth/login')
                ? http.Response(
                  cuerpoDeSesion(accessToken: 'at_1', refreshToken: 'rt_1'),
                  200,
                )
                : http.Response(cuerpo, status),
      );

      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');

      final respuesta = exigirRespuesta(await armado.cliente.get('/companies'));

      expect(
        deNegocio(armado.vistas),
        hasLength(1),
        reason: 'sólo el 401 dispara el reintento',
      );
      expect(
        armado.gestor.estado,
        isA<Autenticado>(),
        reason: 'la autorización no es la autenticación: la sesión sigue viva',
      );

      return respuesta;
    }

    test('un 402 restricted llega intacto y no toca la sesión', () async {
      final respuesta = await pedirCon(
        402,
        '{"code":"subscription_restricted","message":"La suscripción no permite esta operación."}',
      );

      expect(respuesta.statusCode, 402);
      expect(respuesta.cuerpo, contains('subscription_restricted'));
    });

    test('los dos 403 llegan intactos, cada uno con su code', () async {
      for (final codigo in ['permission_missing', 'module_disabled']) {
        final respuesta = await pedirCon(403, '{"code":"$codigo"}');

        expect(respuesta.statusCode, 403);
        expect(respuesta.cuerpo, contains(codigo));
      }
    });

    test('un 409 de negocio llega intacto', () async {
      final respuesta = await pedirCon(
        409,
        '{"code":"contrato_con_sucesor","message":"x"}',
      );

      expect(respuesta.statusCode, 409);
    });

    test('un 404 llega intacto', () async {
      expect((await pedirCon(404, '{"code":"no_encontrado"}')).statusCode, 404);
    });
  });

  group('Fallos de transporte', () {
    test('no se reintentan: no hubo respuesta que interpretar', () async {
      var peticiones = 0;

      final armado = construir((peticion) async {
        if (peticion.url.path.endsWith('/auth/login')) {
          return http.Response(
            cuerpoDeSesion(accessToken: 'at_1', refreshToken: 'rt_1'),
            200,
          );
        }

        peticiones++;
        throw http.ClientException('cortado');
      });

      await armado.gestor.iniciarSesion(email: 'a@b.mx', password: 'x');

      expect(
        exigirFallo(await armado.cliente.post('/clients', json: {'a': 1})),
        isA<ApiSinConexionFailure>(),
      );
      expect(
        peticiones,
        1,
        reason:
            'reintentar a ciegas un POST que quizá sí llegó lo duplicaría, '
            'y todavía no existe Idempotency-Key',
      );
    });
  });
}
