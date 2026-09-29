// Integration Foundation IF-1 — la dirección del backend.
//
// Estas pruebas defienden dos cosas que, si fallan, fallan en silencio y caro:
// que una URL mal configurada NO deje arrancar la aplicación, y que un token de
// sesión no pueda viajar sin cifrar por una red.

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/error/failure.dart';

void main() {
  ApiConfig exigirValida(String raw) {
    final resultado = ApiConfig.resolve(raw: raw);

    return resultado.when(
      ok: (config) => config,
      failure:
          (failure) =>
              fail('«$raw» debería ser válida y dio: ${failure.message}'),
    );
  }

  void exigirRechazada(String raw, {String? porque}) {
    final resultado = ApiConfig.resolve(raw: raw);

    resultado.when(
      ok:
          (config) => fail(
            '«$raw» debería rechazarse${porque == null ? '' : ' ($porque)'} '
            'y se aceptó como $config',
          ),
      failure: (failure) => expect(failure, isA<ApiConfigFailure>()),
    );
  }

  group('Normalización', () {
    test('conserva esquema, host y puerto', () {
      expect(
        exigirValida('http://localhost:5199').baseUrl.toString(),
        'http://localhost:5199',
      );
    });

    test('recorta la barra final', () {
      // Sin esto, componer una ruta produciría `//api/v1/...`.
      expect(
        exigirValida('http://localhost:5199/').baseUrl.toString(),
        'http://localhost:5199',
      );
    });

    test('un host sin puerto es válido y no inventa uno', () {
      expect(
        exigirValida('https://api.seventra.mx').baseUrl.toString(),
        'https://api.seventra.mx',
      );
    });

    test('se ignora la diferencia de mayúsculas en el host', () {
      expect(exigirValida('http://LOCALHOST:5199').baseUrl.host, 'localhost');
    });
  });

  group('Formas rechazadas', () {
    test('vacío: no configurado', () => exigirRechazada(''));

    test('sólo espacios', () => exigirRechazada('   '));

    test('sin esquema', () {
      // `Uri.tryParse('localhost:5199')` toma `localhost` COMO esquema y deja el
      // host vacío. Es la sorpresa silenciosa que esta comprobación corta.
      exigirRechazada('localhost:5199', porque: 'sin esquema');
    });

    test('esquema que no entendemos', () => exigirRechazada('ftp://servidor'));

    test('ruta base: el prefijo /api/v1 lo pone la aplicación', () {
      exigirRechazada(
        'http://localhost:5199/api/v1',
        porque: 'duplicaría el prefijo',
      );
      exigirRechazada(
        'https://api.seventra.mx/seventra',
        porque: 'subpath no soportado en IF-1',
      );
    });

    test(
      'parámetros de consulta',
      () => exigirRechazada('http://localhost:5199?x=1'),
    );

    test('fragmento', () => exigirRechazada('http://localhost:5199#algo'));

    test('credenciales en la URL', () {
      // Viajarían en cada registro y en cada mensaje de error.
      exigirRechazada('https://usuario:clave@api.seventra.mx');
    });

    test('no es una URL', () => exigirRechazada('http://[esto no es un host'));
  });

  group('La regla de HTTPS', () {
    test('http sirve para la máquina local, y sólo para ella', () {
      expect(exigirValida('http://localhost:5199').baseUrl.scheme, 'http');
      expect(exigirValida('http://127.0.0.1:5199').baseUrl.scheme, 'http');
      expect(exigirValida('http://[::1]:5199').baseUrl.scheme, 'http');
    });

    test('una IP PRIVADA no es la máquina local', () {
      // La lista de locales es cerrada a propósito: `192.168.x.x` es la RED, y
      // tratarla como local es exactamente cómo un despliegue de oficina acaba
      // enviando tokens de sesión en claro por el cableado.
      exigirRechazada(
        'http://192.168.1.50:5199',
        porque: 'es red, no esta máquina',
      );
      exigirRechazada(
        'http://10.0.0.5:5199',
        porque: 'es red, no esta máquina',
      );
    });

    test('un dominio por http se rechaza', () {
      exigirRechazada('http://api.seventra.mx');
    });

    test('https se permite en cualquier host', () {
      expect(exigirValida('https://api.seventra.mx').baseUrl.scheme, 'https');
      expect(exigirValida('https://192.168.1.50:8443').baseUrl.scheme, 'https');
    });

    test('esMaquinaLocal reconoce exactamente tres nombres', () {
      expect(ApiConfig.esMaquinaLocal('localhost'), isTrue);
      expect(ApiConfig.esMaquinaLocal('127.0.0.1'), isTrue);
      expect(ApiConfig.esMaquinaLocal('::1'), isTrue);

      expect(ApiConfig.esMaquinaLocal('127.0.0.2'), isFalse);
      expect(ApiConfig.esMaquinaLocal('192.168.1.1'), isFalse);
      expect(ApiConfig.esMaquinaLocal('localhost.evil.com'), isFalse);
    });
  });

  group('El prefijo de versión', () {
    final config = ApiConfig.resolve(
      raw: 'http://localhost:5199',
    ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

    test('compone la ruta con el prefijo y sin barra doble', () {
      expect(
        config.resolver('/companies/abc/employees').toString(),
        'http://localhost:5199/api/v1/companies/abc/employees',
      );
    });

    test('codifica los parámetros de consulta', () {
      final uri = config.resolver('/companies/abc/employees', {
        'query': 'Juan Pérez',
        'limit': '50',
      });

      expect(uri.path, '/api/v1/companies/abc/employees');
      expect(uri.queryParameters['query'], 'Juan Pérez');
      expect(uri.query, contains('Juan+P%C3%A9rez'));
    });

    test('una consulta vacía no deja un «?» colgando', () {
      expect(
        config.resolver('/companies', const {}).toString(),
        'http://localhost:5199/api/v1/companies',
      );
    });

    test('un consumidor NO puede duplicar el prefijo', () {
      // Sin esta comprobación, `/api/v1/companies` produciría
      // `/api/v1/api/v1/companies` y un 404 que nadie sabría explicar.
      expect(() => config.resolver('/api/v1/companies'), throwsArgumentError);
      expect(() => config.resolver('/api/v1'), throwsArgumentError);
    });

    test('una ruta que no empieza por «/» se rechaza', () {
      expect(() => config.resolver('companies'), throwsArgumentError);
    });

    test('el prefijo tiene un solo dueño', () {
      expect(ApiConfig.rutaDeVersion, '/api/v1');
    });
  });
}
