// Integration Foundation IF-2 — las tres llamadas de `/auth`.
//
// Sin backend: `MockClient` responde lo que cada prueba necesita, pero el resto
// de la pila es real (ApiClient, composición de la URL, parser de errores), así
// que lo que se afirma es lo que de verdad saldría por el cable.
//
// Los códigos del backend están verificados sobre su código: `credenciales_invalidas`
// (401), `email_no_verificado` y `cuenta_suspendida` (403), `cuenta_bloqueada`
// (423), `refresh_invalido` y `refresh_reutilizado` (401), y el 429 del limitador,
// que NO sigue el contrato `{code, message}`.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/auth/auth_api.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/core/logging/app_logger.dart';

void main() {
  final config = ApiConfig.resolve(
    raw: 'http://localhost:5199',
  ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

  /// La respuesta real de `SessionResponse`, en `camelCase` y con
  /// `DateTimeOffset` como lo escribe `System.Text.Json`.
  String cuerpoDeSesion({
    String accessToken = 'at_de_acceso_1',
    String refreshToken = 'rt_de_refresco_1',
    String? displayName = 'Ana Torres',
    String? email = 'ana@seventra.mx',
  }) => jsonEncode({
    'accessToken': accessToken,
    'accessExpiresAt': '2026-09-28T12:30:00.000+00:00',
    'refreshToken': refreshToken,
    'refreshExpiresAt': '2026-10-12T12:00:00.000+00:00',
    'sessionId': '0193f0a0-0000-7000-8000-000000000001',
    'displayName': displayName,
    'email': email,
  });

  ({AuthApi api, List<http.Request> vistas}) construir(
    Future<http.Response> Function(http.Request) responder, {
    Duration? timeoutDelCliente,
  }) {
    final vistas = <http.Request>[];

    final cliente = ApiClient(
      config: config,
      cliente: MockClient((peticion) async {
        vistas.add(peticion);
        return responder(peticion);
      }),
      logger: AppLogger.console(),
      timeout: timeoutDelCliente ?? ApiClient.timeoutPorOmision,
    );

    return (api: AuthApi(cliente), vistas: vistas);
  }

  TokensDeSesion exigirTokens(Result<TokensDeSesion> resultado) =>
      resultado.when(
        ok: (tokens) => tokens,
        failure: (f) => fail('Se esperaban tokens y llegó: ${f.message}'),
      );

  Failure exigirFallo(Result<Object?> resultado) => resultado.when(
    ok: (_) => fail('Se esperaba un fallo y la llamada salió bien'),
    failure: (failure) => failure,
  );

  ApiHttpFailure exigirHttp(Result<Object?> resultado) {
    final fallo = exigirFallo(resultado);

    return fallo is ApiHttpFailure
        ? fallo
        : fail('Se esperaba un fallo HTTP y llegó ${fallo.runtimeType}');
  }

  group('Login', () {
    test('va a /api/v1/auth/login con correo y contraseña', () async {
      final armado = construir(
        (_) async => http.Response(cuerpoDeSesion(), 200),
      );

      await armado.api.iniciarSesion(
        email: 'ana@seventra.mx',
        password: 'Sup3rSecreta!',
      );

      final peticion = armado.vistas.single;

      expect(peticion.method, 'POST');
      expect(peticion.url.path, '/api/v1/auth/login');
      expect(jsonDecode(peticion.body), {
        'email': 'ana@seventra.mx',
        'password': 'Sup3rSecreta!',
      });
    });

    test('lee los cinco campos y normaliza los instantes a UTC', () async {
      final armado = construir(
        (_) async => http.Response(cuerpoDeSesion(), 200),
      );

      final tokens = exigirTokens(
        await armado.api.iniciarSesion(email: 'a@b.mx', password: 'x'),
      );

      expect(tokens.accessToken, 'at_de_acceso_1');
      expect(tokens.refreshToken, 'rt_de_refresco_1');
      expect(tokens.sessionId, '0193f0a0-0000-7000-8000-000000000001');
      expect(tokens.accessExpiresAt, DateTime.utc(2026, 9, 28, 12, 30));
      expect(tokens.accessExpiresAt.isUtc, isTrue);
      expect(tokens.refreshExpiresAt, DateTime.utc(2026, 10, 12, 12));
      expect(tokens.displayName, 'Ana Torres');
      expect(tokens.email, 'ana@seventra.mx');
    });

    test(
      'NO manda Authorization: todavía no hay nada con qué firmar',
      () async {
        final armado = construir(
          (_) async => http.Response(cuerpoDeSesion(), 200),
        );

        await armado.api.iniciarSesion(email: 'a@b.mx', password: 'x');

        expect(
          armado.vistas.single.headers.containsKey('Authorization'),
          isFalse,
        );
      },
    );

    test('NO manda Cookie: el escritorio no gestiona cookies', () async {
      final armado = construir(
        (_) async => http.Response(cuerpoDeSesion(), 200),
      );

      await armado.api.iniciarSesion(email: 'a@b.mx', password: 'x');

      expect(armado.vistas.single.headers.containsKey('Cookie'), isFalse);
    });

    test('IGNORA el Set-Cookie del backend y usa el cuerpo', () async {
      // El backend escribe la cookie de refresco para su cliente web.
      // `package:http` no la guarda ni la reenvía, y el token que vale aquí es
      // el del cuerpo. Por eso IF-2 no necesita ni un cambio en el servidor.
      final armado = construir(
        (_) async => http.Response(
          cuerpoDeSesion(),
          200,
          headers: {
            'set-cookie':
                'seventra_refresh=rt_de_la_cookie; Path=/api/v1/auth; HttpOnly',
          },
        ),
      );

      final tokens = exigirTokens(
        await armado.api.iniciarSesion(email: 'a@b.mx', password: 'x'),
      );

      expect(tokens.refreshToken, 'rt_de_refresco_1');
      expect(tokens.refreshToken, isNot('rt_de_la_cookie'));
    });

    test('401 credenciales_invalidas', () async {
      final armado = construir(
        (_) async => http.Response(
          '{"code":"credenciales_invalidas","message":"Correo o contraseña incorrectos."}',
          401,
        ),
      );

      final fallo = exigirHttp(
        await armado.api.iniciarSesion(email: 'a@b.mx', password: 'mala'),
      );

      expect(fallo.statusCode, 401);
      expect(fallo.codigo, 'credenciales_invalidas');
    });

    test('423 cuenta_bloqueada se distingue de un 401', () async {
      // Son dos arreglos distintos: uno es «te equivocaste», el otro «espera
      // quince minutos». Colapsarlos haría que el usuario siguiera intentándolo.
      final armado = construir(
        (_) async => http.Response(
          '{"code":"cuenta_bloqueada","message":"Demasiados intentos fallidos."}',
          423,
        ),
      );

      final fallo = exigirHttp(
        await armado.api.iniciarSesion(email: 'a@b.mx', password: 'x'),
      );

      expect(fallo.statusCode, 423);
      expect(fallo.codigo, 'cuenta_bloqueada');
    });

    test('los dos 403 del login se distinguen por su code', () async {
      for (final codigo in ['email_no_verificado', 'cuenta_suspendida']) {
        final armado = construir(
          (_) async => http.Response('{"code":"$codigo","message":"x"}', 403),
        );

        final fallo = exigirHttp(
          await armado.api.iniciarSesion(email: 'a@b.mx', password: 'x'),
        );

        expect(fallo.statusCode, 403);
        expect(fallo.codigo, codigo);
      }
    });

    test('el 429 del limitador no rompe nada aunque no sea JSON', () async {
      final armado = construir(
        (_) async => http.Response('Too Many Requests', 429),
      );

      final fallo = exigirHttp(
        await armado.api.iniciarSesion(email: 'a@b.mx', password: 'x'),
      );

      expect(fallo.statusCode, 429);
      expect(fallo.message, isNotEmpty);
    });

    test(
      'un cuerpo que no es JSON con 200 no deja escapar FormatException',
      () async {
        final armado = construir(
          (_) async => http.Response('<html>proxy</html>', 200),
        );

        expect(
          exigirFallo(
            await armado.api.iniciarSesion(email: 'a@b.mx', password: 'x'),
          ),
          isA<ApiJsonInvalidoFailure>(),
        );
      },
    );

    test(
      'falta un campo obligatorio: se nombra el campo, NUNCA el valor',
      () async {
        final armado = construir(
          (_) async => http.Response(
            jsonEncode({
              'accessToken': 'at_secreto_que_no_debe_aparecer',
              'accessExpiresAt': '2026-09-28T12:30:00.000+00:00',
              'sessionId': '0193f0a0-0000-7000-8000-000000000001',
            }),
            200,
          ),
        );

        final fallo = exigirFallo(
          await armado.api.iniciarSesion(email: 'a@b.mx', password: 'x'),
        );

        expect(fallo, isA<ApiRespuestaInesperadaFailure>());
        expect(fallo.message, contains('refreshToken'));
        expect(fallo.message, contains('refreshExpiresAt'));
        expect(
          fallo.message,
          isNot(contains('at_secreto_que_no_debe_aparecer')),
        );
      },
    );

    test('una caducidad ilegible cuenta como campo ausente', () async {
      final armado = construir(
        (_) async => http.Response(
          jsonEncode({
            'accessToken': 'at',
            'accessExpiresAt': 'el jueves',
            'refreshToken': 'rt',
            'refreshExpiresAt': '2026-10-12T12:00:00.000+00:00',
            'sessionId': 's',
          }),
          200,
        ),
      );

      final fallo = exigirFallo(
        await armado.api.iniciarSesion(email: 'a@b.mx', password: 'x'),
      );

      expect(fallo.message, contains('accessExpiresAt'));
    });

    test(
      'un fallo de transporte llega como tal, sin convertirse en 401',
      () async {
        final armado = construir(
          (_) async => throw http.ClientException('cortado'),
        );

        expect(
          exigirFallo(
            await armado.api.iniciarSesion(email: 'a@b.mx', password: 'x'),
          ),
          isA<ApiSinConexionFailure>(),
        );
      },
    );
  });

  group('El plazo del login es mayor que el general', () {
    test('son 30 segundos frente a los 20 de una petición normal', () {
      expect(AuthApi.timeoutDeLogin, const Duration(seconds: 30));
      expect(
        AuthApi.timeoutDeLogin,
        greaterThan(ApiClient.timeoutPorOmision),
        reason: 'el hash de contraseña del servidor es lento a propósito',
      );
    });

    test(
      'y el login lo impone de verdad, por encima del plazo del cliente',
      () async {
        // El cliente se construye con un plazo general absurdo de 1 ms. Si el
        // login no pasara el suyo, esta llamada se cortaría; como lo pasa, la
        // respuesta con 40 ms de retraso llega bien.
        final armado = construir((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return http.Response(cuerpoDeSesion(), 200);
        }, timeoutDelCliente: const Duration(milliseconds: 1));

        expect(
          (await armado.api.iniciarSesion(email: 'a@b.mx', password: 'x')).isOk,
          isTrue,
        );
      },
    );

    test('el refresco, en cambio, usa el plazo general', () async {
      final armado = construir((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return http.Response(cuerpoDeSesion(), 200);
      }, timeoutDelCliente: const Duration(milliseconds: 1));

      expect(
        exigirFallo(await armado.api.refrescar(refreshToken: 'rt')),
        isA<ApiTimeoutFailure>(),
      );
    });
  });

  group('Refresco', () {
    test('manda el token EN EL CUERPO a /api/v1/auth/refresh', () async {
      final armado = construir(
        (_) async => http.Response(
          cuerpoDeSesion(
            accessToken: 'at_de_acceso_2',
            refreshToken: 'rt_de_refresco_2',
            displayName: null,
            email: null,
          ),
          200,
        ),
      );

      final tokens = exigirTokens(
        await armado.api.refrescar(refreshToken: 'rt_de_refresco_1'),
      );

      final peticion = armado.vistas.single;

      expect(peticion.url.path, '/api/v1/auth/refresh');
      expect(jsonDecode(peticion.body), {'refreshToken': 'rt_de_refresco_1'});
      expect(tokens.refreshToken, 'rt_de_refresco_2');
    });

    test('el refresco NO reenvía la identidad, y eso es normal', () async {
      // El backend responde `SessionResponse.From(tokens, account: null)`.
      final armado = construir(
        (_) async =>
            http.Response(cuerpoDeSesion(displayName: null, email: null), 200),
      );

      final tokens = exigirTokens(
        await armado.api.refrescar(refreshToken: 'rt'),
      );

      expect(tokens.displayName, isNull);
      expect(tokens.email, isNull);
      expect(tokens.accessToken, isNotEmpty);
    });

    test('distingue refresh_invalido de refresh_reutilizado', () async {
      // El segundo es grave: significa que el backend detectó un canje repetido
      // y revocó la sesión COMPLETA.
      for (final codigo in ['refresh_invalido', 'refresh_reutilizado']) {
        final armado = construir(
          (_) async => http.Response('{"code":"$codigo","message":"x"}', 401),
        );

        final fallo = exigirHttp(
          await armado.api.refrescar(refreshToken: 'rt'),
        );

        expect(fallo.statusCode, 401);
        expect(fallo.codigo, codigo);
      }
    });

    test('un 500 no es un rechazo del token', () async {
      final armado = construir((_) async => http.Response('', 500));

      expect(
        exigirHttp(await armado.api.refrescar(refreshToken: 'rt')).statusCode,
        500,
      );
    });
  });

  group('Cierre', () {
    test('va a /api/v1/auth/logout firmado con el token de acceso', () async {
      final armado = construir((_) async => http.Response('', 204));

      final resultado = await armado.api.cerrarSesion(
        accessToken: 'at_de_acceso_1',
      );

      expect(resultado.isOk, isTrue);
      expect(armado.vistas.single.url.path, '/api/v1/auth/logout');
      expect(
        armado.vistas.single.headers['Authorization'],
        'Bearer at_de_acceso_1',
      );
    });

    test('un 204 con cuerpo vacío es éxito, no un JSON roto', () async {
      final armado = construir((_) async => http.Response('', 204));

      expect((await armado.api.cerrarSesion(accessToken: 'at')).isOk, isTrue);
    });

    test('si el backend no responde, el fallo se reporta', () async {
      // Quien llame decide qué hacer: el gestor lo trata como best-effort.
      final armado = construir(
        (_) async => throw http.ClientException('caído'),
      );

      expect(
        exigirFallo(await armado.api.cerrarSesion(accessToken: 'at')),
        isA<ApiSinConexionFailure>(),
      );
    });
  });
}
