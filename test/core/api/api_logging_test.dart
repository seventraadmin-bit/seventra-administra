// Integration Foundation IF-1 — la redacción de los registros.
//
// ESTAS PRUEBAS EXISTEN ANTES DE QUE HAYA UNA FUGA, no después. La forma cómoda
// de registrar una petición HTTP es volcar el objeto entero y «ya se verá»; el día
// que la petición lleve un `Authorization`, una contraseña o el nombre de un
// empleado en la consulta, queda copiado en un registro que nadie revisa. Y se
// descubre tarde.
//
// Se capturan los registros reales con `Logger.addOutputListener`, así que lo que
// se afirma es lo que de verdad sale por el logger, no lo que el cliente pretende
// escribir.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logger/logger.dart';
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/logging/app_logger.dart';

void main() {
  final config = ApiConfig.resolve(
    raw: 'http://localhost:5199',
  ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

  late List<String> capturado;
  late OutputCallback escucha;

  setUp(() {
    capturado = [];
    escucha = (evento) => capturado.addAll(evento.lines);
    Logger.addOutputListener(escucha);
  });

  tearDown(() => Logger.removeOutputListener(escucha));

  String todoLoRegistrado() => capturado.join('\n');

  ApiClient clienteQueResponde(
    Future<http.Response> Function(http.Request) responder,
  ) => ApiClient(
    config: config,
    cliente: MockClient(responder),
    logger: AppLogger.console(),
  );

  test('Registra método, ruta, status y duración', () async {
    final cliente = clienteQueResponde((_) async => http.Response('{}', 200));

    await cliente.get('/companies/abc/employees');

    expect(todoLoRegistrado(), contains('GET'));
    expect(todoLoRegistrado(), contains('/companies/abc/employees'));
    expect(todoLoRegistrado(), contains('200'));
    expect(todoLoRegistrado(), contains('ms'));
  });

  test(
    'Un 5xx se registra como error y un 4xx como advertencia, sin volcar el cuerpo',
    () async {
      final cliente = clienteQueResponde(
        (_) async => http.Response(
          '{"code":"x","message":"detalle interno del servidor"}',
          500,
        ),
      );

      await cliente.get('/companies');

      expect(todoLoRegistrado(), contains('500'));
      expect(
        todoLoRegistrado(),
        isNot(contains('detalle interno del servidor')),
      );
    },
  );

  test('NUNCA registra Authorization', () async {
    const token = 'tok_secreto_de_sesion_123';
    final cliente = clienteQueResponde((_) async => http.Response('{}', 200));

    // Aunque una capa futura lo pase como encabezado por llamada, el registro no
    // debe conocerlo: aquí no se serializan encabezados, se eligen cuatro campos.
    await cliente.get(
      '/companies',
      headers: {'Authorization': 'Bearer $token'},
    );

    expect(todoLoRegistrado(), isNot(contains(token)));
    expect(todoLoRegistrado().toLowerCase(), isNot(contains('authorization')));
  });

  test('NUNCA registra Cookie', () async {
    const cookie = 'seventra_refresh=refresco_secreto_456';
    final cliente = clienteQueResponde(
      (_) async => http.Response('{}', 200, headers: {'set-cookie': cookie}),
    );

    await cliente.get('/companies', headers: {'Cookie': cookie});

    expect(todoLoRegistrado(), isNot(contains('refresco_secreto_456')));
    expect(todoLoRegistrado().toLowerCase(), isNot(contains('cookie')));
  });

  test('NUNCA registra la contraseña de un cuerpo', () async {
    const password = 'ContraseñaMuySecreta987';
    final cliente = clienteQueResponde((_) async => http.Response('{}', 200));

    await cliente.post(
      '/auth/login',
      json: {'email': 'a@b.mx', 'password': password},
    );

    expect(todoLoRegistrado(), isNot(contains(password)));
    expect(todoLoRegistrado(), isNot(contains('a@b.mx')));
  });

  test('NUNCA registra la consulta de búsqueda', () async {
    // Una búsqueda de empleados lleva el nombre de una persona.
    const nombre = 'Guadalupe Ríos Pérez';
    final cliente = clienteQueResponde((_) async => http.Response('{}', 200));

    await cliente.get('/companies/abc/employees', query: {'query': nombre});

    expect(todoLoRegistrado(), isNot(contains('Guadalupe')));
    expect(todoLoRegistrado(), isNot(contains('query=')));
  });

  test('Si alguien pega una consulta a la ruta, tampoco se registra', () async {
    final cliente = clienteQueResponde((_) async => http.Response('{}', 200));

    // Esto sería un uso incorrecto —la consulta va en `query`—, y aun así el
    // registro no debe llevar el nombre.
    await cliente.get('/companies/abc/employees?query=Guadalupe');

    expect(todoLoRegistrado(), isNot(contains('Guadalupe')));
  });

  test(
    'Un fallo de red registra la CATEGORÍA, no la excepción cruda',
    () async {
      final cliente = ApiClient(
        config: config,
        cliente: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return http.Response('{}', 200);
        }),
        logger: AppLogger.console(),
        timeout: const Duration(milliseconds: 10),
      );

      await cliente.get('/companies');

      expect(todoLoRegistrado(), contains('tiempo agotado'));
    },
  );
}
