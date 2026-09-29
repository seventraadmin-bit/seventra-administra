// Integration Foundation IF-1 — los límites de la etapa, verificados sobre el
// árbol de código.
//
// ESTAS PRUEBAS NO MIRAN COMPORTAMIENTO, MIRAN ALCANCE. IF-1 construye el
// transporte y NADA más: sin autenticación, sin ninguna pantalla conectada y con
// un solo dueño del prefijo de versión. Los tres son invariantes que se rompen sin
// darse cuenta —basta un `Authorization` «temporal» o un repositorio que empiece a
// llamar al cliente— y que después cuesta mucho revertir.
//
// Leen los archivos reales, así que no se pueden satisfacer por accidente.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Todos los `.dart` de `lib/`, excluyendo lo generado.
  List<File> fuentesDeLib() =>
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
          .toList();

  test('El literal /api/v1 tiene UN SOLO dueño en todo lib/', () {
    // Es lo que hace que migrar a /api/v2 sea cambiar una constante y no doscientos
    // repositorios. Si aparece una segunda aparición, esta prueba la señala con su
    // archivo y su línea.
    //
    // SE IGNORAN LOS COMENTARIOS, y no es una concesión: la primera versión de esta
    // prueba contó ocho apariciones, siete de ellas en la documentación que explica
    // por qué el prefijo tiene un solo dueño. Un guardia que se dispara contra su
    // propia explicación obliga a borrar la explicación, que es justo lo contrario
    // de lo que se quiere. Es el cuarto tropiezo del proyecto con lo mismo —el
    // backend lo tuvo tres veces con `COMMENT ON`— así que aquí se corrige el
    // guardia, no el texto.
    //
    // Y se busca el literal ENTRE COMILLAS: `'/api/v1'` es el valor; el mismo texto
    // dentro de un mensaje al usuario —«el prefijo /api/v1 lo pone la
    // aplicación»— es prosa, no un segundo dueño.
    final apariciones = <String>[];

    for (final archivo in fuentesDeLib()) {
      final lineas = archivo.readAsLinesSync();

      for (var i = 0; i < lineas.length; i++) {
        final linea = lineas[i];

        if (linea.trimLeft().startsWith('//')) continue;
        if (linea.contains("'/api/v1'") || linea.contains('"/api/v1"')) {
          apariciones.add('${archivo.path}:${i + 1}');
        }
      }
    }

    expect(
      apariciones,
      hasLength(1),
      reason:
          'El prefijo debe vivir sólo en ApiConfig.rutaDeVersion. Apariciones: $apariciones',
    );

    expect(apariciones.single, contains('api_config.dart'));
  });

  test('NINGUNA feature consume todavía el cliente HTTP', () {
    // IF-1 es cimiento: conectar una pantalla es IF-2 y siguientes. Si una feature
    // empezara a usar `ApiClient` antes de que exista sesión, tendría que inventar
    // su propia autenticación —y ésa es exactamente la dispersión que Integration
    // Foundation viene a evitar.
    final infractores = <String>[];

    for (final archivo in fuentesDeLib()) {
      if (!archivo.path.contains('features')) continue;

      final contenido = archivo.readAsStringSync();

      if (contenido.contains('ApiClient') ||
          contenido.contains('apiClientProvider') ||
          contenido.contains('core/api/')) {
        infractores.add(archivo.path);
      }
    }

    expect(
      infractores,
      isEmpty,
      reason: 'Ninguna feature debe consumir la capa HTTP en IF-1.',
    );
  });

  test('La capa HTTP de IF-1 NO implementa autenticación', () {
    // Sin encabezado `Authorization`, sin tokens, sin refresco y sin login: la
    // política de sesión no puede vivir en el transporte.
    //
    // LA FRONTERA SE AJUSTÓ EN IF-2, y el invariante que protege no cambió. IF-2
    // añadió `api_client_autenticado.dart` a esta misma carpeta —un DECORADOR que
    // sí firma y sí reacciona al 401—, y esa es precisamente la separación
    // buscada: el cliente desnudo sigue sin saber qué es un token, porque si
    // autenticara, pedir un token necesitaría un token. Así que lo que se
    // comprueba ya no es «esta carpeta no autentica», que sería falso, sino lo que
    // siempre se quiso decir: **estas piezas de IF-1 no autentican**. El decorador
    // tiene sus propias pruebas, y `auth_arquitectura_test` verifica que el
    // desnudo siga limpio.
    const deIF1 = [
      'lib/core/api/api_client.dart',
      'lib/core/api/api_respuesta.dart',
      'lib/core/api/api_error_parser.dart',
      'lib/core/api/api_providers.dart',
      'lib/core/api/json_api.dart',
    ];

    final prohibidos = <String, List<String>>{};

    for (final archivo in deIF1.map(File.new)) {
      final contenido = archivo.readAsStringSync();
      final encontrados = <String>[];

      // Se buscan USOS, no menciones: los comentarios de estas clases explican a
      // propósito qué NO hacen y por qué, y eso debe seguir siendo legible.
      for (final patron in [
        "'Authorization'",
        '"Authorization"',
        'accessToken',
        'refreshToken',
        'bearer ',
        'Bearer \$',
      ]) {
        if (contenido.contains(patron)) encontrados.add(patron);
      }

      if (encontrados.isNotEmpty) prohibidos[archivo.path] = encontrados;
    }

    expect(prohibidos, isEmpty, reason: 'IF-1 no autentica: $prohibidos');
  });

  test('No se usan las funciones estáticas de package:http', () {
    // `http.get(...)` crea su propio Client, no se puede sustituir en pruebas y
    // abre una conexión nueva cada vez. Todo pasa por el Client inyectado.
    final infractores = <String>[];

    for (final archivo in fuentesDeLib()) {
      final contenido = archivo.readAsStringSync();

      for (final estatico in [
        'http.get(',
        'http.post(',
        'http.put(',
        'http.patch(',
        'http.delete(',
        'http.read(',
      ]) {
        if (contenido.contains(estatico)) {
          infractores.add('${archivo.path} → $estatico');
        }
      }
    }

    expect(infractores, isEmpty);
  });

  test('IF-1 no trajo ningún paquete que se decidió NO usar', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    for (final descartado in [
      'dio:',
      'retrofit:',
      'chopper:',
      'connectivity_plus:',
      'freezed:',
      'json_serializable:',
      'grpc:',
    ]) {
      expect(
        pubspec,
        isNot(contains(descartado)),
        reason: '$descartado se descartó con evidencia',
      );
    }

    // Y sí trajo el que se eligió.
    expect(pubspec, contains('http: ^1.6.0'));
  });
}
