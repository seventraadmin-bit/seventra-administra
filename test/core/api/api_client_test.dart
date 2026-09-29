// Integration Foundation IF-1 — el transporte HTTP.
//
// Sin backend: `MockClient` responde lo que cada prueba necesita. Lo que se
// defiende aquí es la FRONTERA del cliente: una respuesta HTTP —cualquiera— vuelve
// como `ApiRespuesta`, y la ausencia de respuesta vuelve como `Failure`, sin que
// ninguna excepción de `dart:io` ni de `package:http` escape.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/api/api_respuesta.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/core/logging/app_logger.dart';

void main() {
  final config = ApiConfig.resolve(
    raw: 'http://localhost:5199',
  ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

  /// Un cliente cuyo transporte es la función dada. Captura la última petición
  /// para poder afirmar sobre método, URL y encabezados.
  ({ApiClient cliente, List<http.BaseRequest> vistas}) construir(
    Future<http.Response> Function(http.Request) responder,
  ) {
    final vistas = <http.BaseRequest>[];

    final mock = MockClient((peticion) async {
      vistas.add(peticion);
      return responder(peticion);
    });

    return (
      cliente: ApiClient(
        config: config,
        cliente: mock,
        logger: AppLogger.console(),
      ),
      vistas: vistas,
    );
  }

  ApiRespuesta exigirRespuesta(Result<ApiRespuesta> resultado) =>
      resultado.when(
        ok: (respuesta) => respuesta,
        failure:
            (failure) =>
                fail('Se esperaba una respuesta y llegó: ${failure.message}'),
      );

  Failure exigirFallo(Result<ApiRespuesta> resultado) => resultado.when(
    ok:
        (respuesta) =>
            fail('Se esperaba un fallo y llegó HTTP ${respuesta.statusCode}'),
    failure: (failure) => failure,
  );

  group('Los cinco verbos', () {
    test('cada uno llega con su método y su URL compuesta', () async {
      for (final (metodo, invocar)
          in <(String, Future<Result<ApiRespuesta>> Function(ApiClient))>[
            ('GET', (c) => c.get('/companies')),
            ('POST', (c) => c.post('/companies', json: {'name': 'X'})),
            ('PUT', (c) => c.put('/companies/1', json: {'name': 'X'})),
            ('PATCH', (c) => c.patch('/companies/1', json: {'name': 'X'})),
            ('DELETE', (c) => c.delete('/companies/1')),
          ]) {
        final armado = construir((_) async => http.Response('{}', 200));

        await invocar(armado.cliente);

        expect(armado.vistas.single.method, metodo);
        expect(armado.vistas.single.url.path, startsWith('/api/v1/companies'));
      }
    });

    test('la consulta se codifica', () async {
      final armado = construir((_) async => http.Response('{}', 200));

      await armado.cliente.get(
        '/companies/1/employees',
        query: {'query': 'Juan Pérez'},
      );

      expect(armado.vistas.single.url.queryParameters['query'], 'Juan Pérez');
    });
  });

  group('Encabezados', () {
    test('Accept siempre, y Content-Type SÓLO cuando hay cuerpo', () async {
      final sinCuerpo = construir((_) async => http.Response('{}', 200));
      await sinCuerpo.cliente.get('/companies');

      expect(sinCuerpo.vistas.single.headers['Accept'], 'application/json');
      expect(
        sinCuerpo.vistas.single.headers.containsKey('Content-Type'),
        isFalse,
        reason:
            'declarar Content-Type en un GET es mentir sobre lo que se envía',
      );

      final conCuerpo = construir((_) async => http.Response('{}', 201));
      await conCuerpo.cliente.post('/companies', json: {'name': 'X'});

      expect(
        conCuerpo.vistas.single.headers['Content-Type'],
        contains('application/json'),
      );
    });

    test('IF-1 NUNCA manda Authorization ni Cookie: eso es de IF-2', () async {
      final armado = construir((_) async => http.Response('{}', 200));

      await armado.cliente.get('/companies');

      final enviados = armado.vistas.single.headers.keys.map(
        (k) => k.toLowerCase(),
      );
      expect(enviados, isNot(contains('authorization')));
      expect(enviados, isNot(contains('cookie')));
    });

    test('se pueden añadir encabezados por llamada', () async {
      final armado = construir((_) async => http.Response('{}', 200));

      await armado.cliente.get('/companies', headers: {'X-Prueba': 'sí'});

      expect(armado.vistas.single.headers['X-Prueba'], 'sí');
    });

    test('el cuerpo JSON se codifica', () async {
      http.Request? capturada;
      final armado = construir((peticion) async {
        capturada = peticion;
        return http.Response('{}', 201);
      });

      await armado.cliente.post(
        '/companies',
        json: {'name': 'Matriz', 'activo': true},
      );

      expect(jsonDecode(capturada!.body), {'name': 'Matriz', 'activo': true});
    });
  });

  group('Respuestas', () {
    test('un objeto JSON se decodifica', () async {
      final armado = construir((_) async => http.Response('{"id":"abc"}', 200));

      final respuesta = exigirRespuesta(
        await armado.cliente.get('/companies/abc'),
      );

      expect(respuesta.esExitosa, isTrue);
      respuesta.comoObjeto().when(
        ok: (objeto) => expect(objeto['id'], 'abc'),
        failure: (f) => fail(f.message),
      );
    });

    test(
      'un ARRAY DESNUDO también: el backend devuelve las dos formas',
      () async {
        final armado = construir(
          (_) async => http.Response('[{"id":"a"},{"id":"b"}]', 200),
        );

        final respuesta = exigirRespuesta(
          await armado.cliente.get('/companies'),
        );

        respuesta.comoLista().when(
          ok: (lista) => expect(lista, hasLength(2)),
          failure: (f) => fail(f.message),
        );
      },
    );

    test('un 204 sin cuerpo no es un error', () async {
      final armado = construir((_) async => http.Response('', 204));

      final respuesta = exigirRespuesta(
        await armado.cliente.delete('/companies/1'),
      );

      expect(respuesta.statusCode, 204);
      respuesta.decodificar().when(
        ok: (valor) => expect(valor, isNull),
        failure: (f) => fail('un cuerpo vacío no es JSON roto: ${f.message}'),
      );
    });

    test(
      'pedir objeto cuando llegó lista es un DESACUERDO DE CONTRATO',
      () async {
        // Distinto de JSON roto: el transporte funcionó, el servidor mandó JSON
        // válido, y lo que no coincide es la forma esperada.
        final armado = construir((_) async => http.Response('[1,2]', 200));

        final respuesta = exigirRespuesta(
          await armado.cliente.get('/companies'),
        );

        respuesta.comoObjeto().when(
          ok: (_) => fail('debería rechazar una lista'),
          failure: (f) => expect(f, isA<ApiRespuestaInesperadaFailure>()),
        );
      },
    );
  });

  group('Los status NO exitosos son RESPUESTAS, no excepciones', () {
    test(
      'los nueve status llegan como ApiRespuesta con su código intacto',
      () async {
        for (final status in [
          400,
          401,
          402,
          403,
          404,
          409,
          413,
          429,
          500,
          503,
        ]) {
          final armado = construir(
            (_) async => http.Response('{"code":"x","message":"y"}', status),
          );

          final respuesta = exigirRespuesta(
            await armado.cliente.get('/companies'),
          );

          expect(respuesta.statusCode, status);
          expect(respuesta.esExitosa, isFalse);
        }
      },
    );

    test('IF-1 no interpreta un 401 ni un 402', () async {
      // No hay logout, no hay estado restringido: sólo una respuesta con su
      // status. Interpretarla es de IF-2 e IF-4.
      final armado = construir(
        (_) async => http.Response('{"code":"subscription_restricted"}', 402),
      );

      final respuesta = exigirRespuesta(
        await armado.cliente.post('/companies', json: {}),
      );

      expect(respuesta.statusCode, 402);
    });
  });

  group('Cuando NO hay respuesta', () {
    test('sin conexión', () async {
      final armado = construir(
        (_) async => throw const SocketException('sin ruta al host'),
      );

      expect(
        exigirFallo(await armado.cliente.get('/companies')),
        isA<ApiSinConexionFailure>(),
      );
    });

    test('tiempo agotado', () async {
      final mock = MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response('{}', 200);
      });

      final cliente = ApiClient(
        config: config,
        cliente: mock,
        logger: AppLogger.console(),
        timeout: const Duration(milliseconds: 20),
      );

      expect(
        exigirFallo(await cliente.get('/companies')),
        isA<ApiTimeoutFailure>(),
      );
    });

    test('el plazo se puede sobrescribir por petición', () async {
      final mock = MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        return http.Response('{}', 200);
      });

      final cliente = ApiClient(
        config: config,
        cliente: mock,
        logger: AppLogger.console(),
        timeout: const Duration(milliseconds: 10),
      );

      // Con el plazo por omisión fallaría; con el de la llamada, no.
      final resultado = await cliente.get(
        '/companies',
        timeout: const Duration(seconds: 5),
      );

      expect(exigirRespuesta(resultado).statusCode, 200);
    });

    test('transporte interrumpido', () async {
      final armado = construir(
        (_) async => throw http.ClientException('conexión cerrada'),
      );

      expect(
        exigirFallo(await armado.cliente.get('/companies')),
        isA<ApiSinConexionFailure>(),
      );
    });

    test('JSON malformado en un 200 NO deja escapar FormatException', () async {
      final armado = construir(
        (_) async => http.Response('{esto no es json', 200),
      );

      final respuesta = exigirRespuesta(await armado.cliente.get('/companies'));

      respuesta.decodificar().when(
        ok: (_) => fail('debería fallar'),
        failure: (f) => expect(f, isA<ApiJsonInvalidoFailure>()),
      );
    });

    test('el mensaje de JSON inválido NO incluye el cuerpo', () async {
      // Podría ser una página de error de un proxy con información de la red
      // interna, y ese texto acaba en pantallas y registros.
      const secreto = 'ADVERTENCIA: proxy-interno-rh.empresa.local';
      final armado = construir(
        (_) async => http.Response('<html>$secreto</html>', 200),
      );

      final respuesta = exigirRespuesta(await armado.cliente.get('/companies'));

      respuesta.decodificar().when(
        ok: (_) => fail('debería fallar'),
        failure: (f) => expect(f.message, isNot(contains(secreto))),
      );
    });

    test('una ruta mal formada no deja escapar ArgumentError', () async {
      final armado = construir((_) async => http.Response('{}', 200));

      // Es un error de programación, pero el contrato público sigue siendo Result.
      expect(
        exigirFallo(await armado.cliente.get('/api/v1/companies')),
        isA<ApiConfigFailure>(),
      );
    });
  });
}
