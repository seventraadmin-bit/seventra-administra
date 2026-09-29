// Integration Foundation IF-1 — el parser de errores del backend.
//
// El backend es uniforme salvo en un sitio: el 429 lo produce el limitador de
// ASP.NET y no sigue el contrato `{code, message}`. Un proxy puede devolver HTML.
// Lo que se defiende aquí es que nada de eso rompa el parser, y que lo que las
// capas siguientes necesitan —status, code, cifras de capacidad— no se pierda.

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/api/api_error_parser.dart';
import 'package:riseg_one/core/api/api_respuesta.dart';
import 'package:riseg_one/core/error/failure.dart';

void main() {
  ApiRespuesta respuesta(int status, String cuerpo) =>
      ApiRespuesta(statusCode: status, headers: const {}, cuerpo: cuerpo);

  group('El formato conocido', () {
    test('extrae code y message', () {
      final fallo = ApiErrorParser.interpretar(
        respuesta(
          403,
          '{"code":"permission_missing","message":"No tienes permiso para esta acción."}',
        ),
      );

      expect(fallo.statusCode, 403);
      expect(fallo.codigo, 'permission_missing');
      expect(fallo.message, 'No tienes permiso para esta acción.');
    });

    test('conserva las cifras de capacidad', () {
      // IF-5 las necesita para decir «tienes X de Y» en vez de un «no» seco.
      final fallo = ApiErrorParser.interpretar(
        respuesta(
          409,
          '{"code":"storage_capacity_exceeded","message":"No alcanza.",'
          '"usedBytes":900,"capacityBytes":1000}',
        ),
      );

      expect(fallo.codigo, 'storage_capacity_exceeded');
      expect(fallo.extra['usedBytes'], 900);
      expect(fallo.extra['capacityBytes'], 1000);
    });

    test('con code pero sin message usa el mensaje de la familia', () {
      final fallo = ApiErrorParser.interpretar(
        respuesta(402, '{"code":"subscription_restricted"}'),
      );

      expect(fallo.codigo, 'subscription_restricted');
      expect(fallo.message, isNotEmpty);
    });

    test('distingue los dos 403 del backend por su code', () {
      // «pide que te concedan el permiso» y «el módulo está apagado para TODA la
      // empresa» son dos arreglos distintos, y el cliente necesita saber cuál
      // ofrecer.
      final sinPermiso = ApiErrorParser.interpretar(
        respuesta(403, '{"code":"permission_missing","message":"a"}'),
      );
      final moduloApagado = ApiErrorParser.interpretar(
        respuesta(403, '{"code":"module_disabled","message":"b"}'),
      );

      expect(sinPermiso.codigo, isNot(moduloApagado.codigo));
    });
  });

  group('Formas que no reconoce', () {
    test('JSON válido con otra forma: dice las CLAVES, nunca los valores', () {
      final fallo = ApiErrorParser.interpretar(
        respuesta(500, '{"traceId":"abc-123","detalleInterno":"ruta/secreta"}'),
      );

      expect(fallo.statusCode, 500);
      expect(
        fallo.codigo,
        isNull,
        reason: 'no se inventa un code que el servidor no envió',
      );
      expect(fallo.message, contains('traceId'));
      expect(fallo.message, isNot(contains('ruta/secreta')));
    });

    test('un cuerpo que NO es JSON no rompe el parser', () {
      // El 429 del limitador y un 502 de proxy llegan así.
      final fallo = ApiErrorParser.interpretar(
        respuesta(429, 'Too Many Requests'),
      );

      expect(fallo.statusCode, 429);
      expect(fallo.message, isNotEmpty);
    });

    test('HTML de un proxy tampoco', () {
      final fallo = ApiErrorParser.interpretar(
        respuesta(502, '<html><body>Bad Gateway</body></html>'),
      );

      expect(fallo.statusCode, 502);
      expect(fallo, isA<ApiHttpFailure>());
    });

    test('un cuerpo largo se RECORTA', () {
      final fallo = ApiErrorParser.interpretar(respuesta(500, 'x' * 5000));

      expect(fallo.message.length, lessThan(400));
      expect(fallo.message, contains('…'));
    });

    test('un cuerpo vacío no rompe nada', () {
      final fallo = ApiErrorParser.interpretar(respuesta(503, ''));

      expect(fallo.statusCode, 503);
      expect(fallo.message, isNotEmpty);
    });
  });

  test('El parser NO interpreta: no decide logout ni modo restringido', () {
    // Sólo traduce. Que un 401 signifique «cierra la sesión» es una decisión de
    // IF-2, y tomarla aquí la esconderia en el transporte.
    final fallo = ApiErrorParser.interpretar(
      respuesta(401, '{"code":"sesion_invalida"}'),
    );

    expect(fallo, isA<ApiHttpFailure>());
    expect(fallo.statusCode, 401);
    expect(fallo.codigo, 'sesion_invalida');
  });
}
