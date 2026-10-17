import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

// EL CONDICIONAL ES LO QUE DEJA COMPILAR ESTE ARCHIVO PARA WEB. `dart:io` no existe
// en el navegador, y de el solo se necesitaban dos preguntas de tipo: estan detras de
// estas dos funciones, con una version por plataforma.
import 'fallo_de_conexion_web.dart'
    if (dart.library.io) 'fallo_de_conexion_io.dart';
import '../config/api_config.dart';
import '../error/failure.dart';
import '../error/result.dart';
import '../logging/app_logger.dart';
import 'api_respuesta.dart';

/// El transporte HTTP hacia el backend SaaS. Infraestructura, nada más.
///
/// LO QUE DEVUELVE Y LO QUE FALLA, que es la decisión central de esta clase:
///
///  · **Hubo respuesta** —cualquier status, incluidos 404, 409 y 500— devuelve
///    `Result.ok(ApiRespuesta)`. No lanza por un status, porque un 409
///    `contrato_con_sucesor` es información de negocio y convertirlo en excepción
///    obligaría a cada repositorio a atraparla para volver a decidir lo mismo.
///  · **No hubo respuesta** —sin red, timeout, transporte roto— devuelve un
///    [ApiFailure]. **Ninguna excepción de `dart:io` ni de `package:http` escapa
///    de aquí**: el contrato público de esta clase es `Result`, y eso es lo que
///    permite que las 77 pantallas del producto no aprendan qué es un
///    `SocketException`.
///
/// NO SABE DE AUTENTICACIÓN. No pone `Authorization`, no conoce tokens y no
/// interpreta un 401: eso es de IF-2, y meterlo aquí haría que cambiar la política
/// de sesión obligara a tocar el transporte.
///
/// NO SABE DE COMPANY. El backend la lleva en la RUTA —verificado en sus 18 grupos
/// de endpoints—, así que añadir un encabezado sería inventar un segundo canal
/// para lo mismo.
class ApiClient {
  ApiClient({
    required ApiConfig config,
    required http.Client cliente,
    required AppLogger logger,
    Duration timeout = timeoutPorOmision,
  }) : _config = config,
       _cliente = cliente,
       _logger = logger,
       _timeout = timeout;

  /// Veinte segundos, y no es un número redondo elegido al azar: el endpoint más
  /// costoso del backend —el listado con `LATERAL`— responde en decenas de
  /// milisegundos contra PostgreSQL, así que esto cubre una red mala con holgura.
  /// Sesenta dejarían la interfaz colgada sin que nadie entienda por qué.
  ///
  /// El plazo mayor que necesitarán login y refresco —el hash de contraseña es
  /// deliberadamente lento en el servidor— pertenece a IF-2 y se pasará por
  /// petición.
  static const Duration timeoutPorOmision = Duration(seconds: 20);

  final ApiConfig _config;
  final http.Client _cliente;
  final AppLogger _logger;
  final Duration _timeout;

  Future<Result<ApiRespuesta>> get(
    String ruta, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) => _enviar('GET', ruta, query: query, headers: headers, timeout: timeout);

  Future<Result<ApiRespuesta>> post(
    String ruta, {
    Object? json,
    Map<String, String>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) => _enviar(
    'POST',
    ruta,
    json: json,
    query: query,
    headers: headers,
    timeout: timeout,
  );

  Future<Result<ApiRespuesta>> put(
    String ruta, {
    Object? json,
    Map<String, String>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) => _enviar(
    'PUT',
    ruta,
    json: json,
    query: query,
    headers: headers,
    timeout: timeout,
  );

  Future<Result<ApiRespuesta>> patch(
    String ruta, {
    Object? json,
    Map<String, String>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) => _enviar(
    'PATCH',
    ruta,
    json: json,
    query: query,
    headers: headers,
    timeout: timeout,
  );

  Future<Result<ApiRespuesta>> delete(
    String ruta, {
    Object? json,
    Map<String, String>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) => _enviar(
    'DELETE',
    ruta,
    json: json,
    query: query,
    headers: headers,
    timeout: timeout,
  );

  /// El camino único. Los cinco verbos delegan aquí para que el trato de los
  /// errores exista una sola vez: cinco copias divergirían justo en el caso de
  /// fallo, que es donde importa.
  ///
  /// Compone un [http.Request] —y no llama a `http.get` ni a sus hermanos
  /// estáticos— por dos razones: los estáticos crean su propio `Client` y no se
  /// pueden sustituir en pruebas, y trabajar con `BaseRequest` deja la puerta
  /// abierta a `MultipartRequest` y a `Client.send` con respuesta en flujo cuando
  /// IF-5 traiga los archivos.
  Future<Result<ApiRespuesta>> _enviar(
    String metodo,
    String ruta, {
    Object? json,
    Map<String, String>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    final Uri uri;

    try {
      uri = _config.resolver(ruta, query);
    } on ArgumentError catch (error) {
      // Una ruta mal formada es un error de PROGRAMACIÓN, no del servidor ni de
      // la red. Se devuelve como fallo de configuración en vez de dejar escapar
      // un ArgumentError para que el contrato de esta clase siga siendo `Result`.
      return Result.failure(
        ApiConfigFailure('Ruta inválida «$ruta»: ${error.message}'),
      );
    }

    final peticion = http.Request(metodo, uri);
    final reloj = Stopwatch()..start();

    peticion.headers['Accept'] = 'application/json';

    if (json != null) {
      // `Content-Type` SÓLO cuando hay cuerpo: declararlo en un GET es mentir
      // sobre lo que se envía.
      peticion.headers['Content-Type'] = 'application/json; charset=utf-8';
      peticion.body = jsonEncode(json);
    }

    if (headers != null) peticion.headers.addAll(headers);

    try {
      final streamed = await _cliente
          .send(peticion)
          .timeout(timeout ?? _timeout);
      final respuesta = await http.Response.fromStream(streamed);

      reloj.stop();
      _registrar(metodo, ruta, respuesta.statusCode, reloj.elapsedMilliseconds);

      return Result.ok(
        ApiRespuesta(
          statusCode: respuesta.statusCode,
          headers: respuesta.headers,
          cuerpo: respuesta.body,
        ),
      );
    } on TimeoutException {
      reloj.stop();
      _registrarFallo(
        metodo,
        ruta,
        'tiempo agotado',
        reloj.elapsedMilliseconds,
      );

      return const Result.failure(
        ApiTimeoutFailure('El servidor tardó demasiado en responder.'),
      );
    } on http.ClientException catch (error) {
      // AQUI SE DISTINGUEN LOS DOS CASOS, y antes eran dos ramas separadas.
      //
      // `IOClient` lanza, ante un fallo de socket, una `ClientException` que ADEMAS
      // `implements SocketException` — el paquete lo documenta y dice que lo hace a
      // proposito. Asi que el objeto es las dos cosas, y `esFalloDeConexion` lo
      // reconoce sin que este archivo tenga que importar `dart:io`.
      //
      // EL COMPORTAMIENTO EN ESCRITORIO NO CAMBIA: el mismo error produce el mismo
      // fallo y el mismo mensaje que cuando eran dos ramas.
      if (esFalloDeConexion(error)) {
        reloj.stop();
        _registrarFallo(metodo, ruta, 'sin conexión', reloj.elapsedMilliseconds);

        return const Result.failure(
          ApiSinConexionFailure('No se pudo conectar con el servidor.'),
        );
      }

      // Conexión interrumpida a mitad, respuesta truncada, cliente ya cerrado.
      reloj.stop();
      _registrarFallo(
        metodo,
        ruta,
        'transporte interrumpido',
        reloj.elapsedMilliseconds,
      );

      return const Result.failure(
        ApiSinConexionFailure('La conexión con el servidor se interrumpió.'),
      );
    } on Exception catch (error) {
      // LOS DOS FALLOS DE `dart:io` QUE NO LLEGAN ENVUELTOS, y sin importarlo.
      //
      // · Una `SocketException` CRUDA. La lanza cualquier `http.Client` que no sea
      //   `IOClient` — un `MockClient` en las pruebas, por ejemplo —, y no es una
      //   `ClientException`, asi que no cae en la rama de arriba. **Lo descubrio una
      //   prueba** al quitar la rama vieja: sin esto, una `SocketException` directa
      //   escapaba y el cliente dejaba de traducirla.
      //
      // · Una `HandshakeException`. `IOClient.send` solo atrapa `SocketException` y
      //   `HttpException`, asi que un fallo de TLS sube crudo.
      //
      // SE RELANZA LO DEMAS, y eso importa: esta rama no puede tragarse un error de
      // programacion que pase por aqui. En web las dos preguntas son `false`, asi
      // que todo relanza y es identico a no tener la rama.
      if (esFalloDeConexion(error)) {
        reloj.stop();
        _registrarFallo(metodo, ruta, 'sin conexión', reloj.elapsedMilliseconds);

        return const Result.failure(
          ApiSinConexionFailure('No se pudo conectar con el servidor.'),
        );
      }

      if (!esFalloDeTls(error)) rethrow;

      reloj.stop();
      _registrarFallo(metodo, ruta, 'TLS rechazado', reloj.elapsedMilliseconds);

      return const Result.failure(
        ApiSinConexionFailure(
          'No se pudo establecer una conexión segura con el servidor.',
        ),
      );
    }
  }

  /// La línea de registro, compuesta CAMPO POR CAMPO.
  ///
  /// Nunca se serializa la petición ni la respuesta: se eligen cuatro datos y se
  /// escriben. Es la misma razón por la que `AuditPayload` del backend es lista
  /// blanca — copiar «lo que haya» es cómo un secreto acaba en un registro que
  /// nadie puede limpiar, y se descubre tarde.
  ///
  /// NO se registran encabezados (ahí viven `Authorization` y `Cookie`), ni
  /// cuerpos, ni **los parámetros de consulta**: una búsqueda de empleados lleva
  /// el nombre de una persona.
  void _registrar(String metodo, String ruta, int statusCode, int ms) {
    final linea = '$metodo ${_sanear(ruta)} → $statusCode (${ms}ms)';

    if (statusCode >= 500) {
      _logger.error(linea);
    } else if (statusCode >= 400) {
      _logger.warning(linea);
    } else {
      _logger.debug(linea);
    }
  }

  void _registrarFallo(String metodo, String ruta, String categoria, int ms) =>
      _logger.warning('$metodo ${_sanear(ruta)} → $categoria (${ms}ms)');

  /// Recorta cualquier consulta que viniera pegada a la ruta.
  ///
  /// La ruta se registra CON sus UUID —hacen falta para correlacionar—, pero si
  /// alguien pasara `/employees?query=Guadalupe` como ruta, el nombre no debe
  /// llegar al registro.
  static String _sanear(String ruta) {
    final corte = ruta.indexOf('?');
    return corte == -1 ? ruta : ruta.substring(0, corte);
  }
}
