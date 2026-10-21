import 'dart:typed_data';

import '../auth/gestor_de_sesion.dart';
import '../error/result.dart';
import 'api_client.dart';
import 'api_respuesta.dart';

/// El cliente HTTP **con sesión**: firma cada petición y reacciona al 401.
///
/// ES UN DECORADOR Y NO UN CAMBIO EN [ApiClient], y la separación es el punto de
/// este archivo. El cliente desnudo sigue existiendo, sigue sin saber qué es un
/// token y sigue siendo el que usa `AuthApi` —si autenticara, pedir un token
/// requeriría un token—. Aquí viven las dos únicas decisiones de política que la
/// sesión impone al transporte:
///
///  1. poner `Authorization: Bearer …` con un token que el gestor garantiza
///     vigente;
///  2. ante un **401**, refrescar y reintentar **exactamente una vez**.
///
/// LO QUE DELIBERADAMENTE NO HACE:
///
///  · no interpreta el **402** (`restricted`), ni el **403** (`permission_missing`
///    o `module_disabled`), ni nada relativo a Company o permisos. Eso es
///    autorización, no autenticación, y son preguntas de IF-4 con respuestas que
///    dependen del módulo. Decidirlas aquí las escondería en el transporte, que es
///    exactamente el error que IF-1 evitó;
///  · no reintenta por tiempo agotado, por falta de red ni por un 5xx. Reintentar
///    a ciegas un `POST` que quizá sí llegó duplicaría una operación de negocio, y
///    este proyecto todavía no tiene `Idempotency-Key`;
///  · no reintenta dos veces. Si el segundo intento también recibe 401, la
///    respuesta se devuelve tal cual: insistir sería pedirle al backend un canje
///    de refresco tras otro, y él responde a la reutilización revocando la sesión
///    completa.
class ApiClientAutenticado {
  const ApiClientAutenticado({
    required ApiClient cliente,
    required GestorDeSesion gestor,
  }) : _cliente = cliente,
       _gestor = gestor;

  final ApiClient _cliente;
  final GestorDeSesion _gestor;

  Future<Result<ApiRespuesta>> get(
    String ruta, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) => _conSesion(
    headers,
    (h) => _cliente.get(ruta, query: query, headers: h, timeout: timeout),
  );

  Future<Result<ApiRespuesta>> post(
    String ruta, {
    Object? json,
    Map<String, String>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) => _conSesion(
    headers,
    (h) => _cliente.post(
      ruta,
      json: json,
      query: query,
      headers: h,
      timeout: timeout,
    ),
  );

  Future<Result<ApiRespuesta>> put(
    String ruta, {
    Object? json,
    Map<String, String>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) => _conSesion(
    headers,
    (h) => _cliente.put(
      ruta,
      json: json,
      query: query,
      headers: h,
      timeout: timeout,
    ),
  );

  Future<Result<ApiRespuesta>> patch(
    String ruta, {
    Object? json,
    Map<String, String>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) => _conSesion(
    headers,
    (h) => _cliente.patch(
      ruta,
      json: json,
      query: query,
      headers: h,
      timeout: timeout,
    ),
  );

  Future<Result<ApiRespuesta>> delete(
    String ruta, {
    Object? json,
    Map<String, String>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) => _conSesion(
    headers,
    (h) => _cliente.delete(
      ruta,
      json: json,
      query: query,
      headers: h,
      timeout: timeout,
    ),
  );

  /// Descarga un binario **firmado**: el logotipo de la empresa, la foto de un
  /// empleado, un documento de contrato.
  ///
  /// ⚠️ **ES EL ÚNICO CAMINO, y conviene saber por qué no sirve `Image.network`.** Dos
  /// razones independientes, las dos del servidor: el `Authorization: Bearer` **no
  /// viaja** en la petición que hace un `<img>`, y la ruta contesta con
  /// `Content-Disposition: attachment` a propósito —«nada inline»—. Así que el binario
  /// se trae por aquí y se pinta desde memoria.
  Future<Result<ApiRespuesta>> getBytes(
    String ruta, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) => _conSesion(
    headers,
    (h) => _cliente.getBytes(ruta, query: query, headers: h, timeout: timeout),
  );

  /// Sube un archivo **firmado**.
  ///
  /// Recibe los bytes y no un flujo por la misma razón que [_conSesion] documenta para
  /// el JSON: esta petición **se puede enviar dos veces** —ante un 401 se refresca y se
  /// repite— y un `MultipartRequest` con un flujo dentro llegaría vacío la segunda vez.
  /// Con los bytes en los argumentos, [ApiClient] la compone de nuevo en cada intento.
  Future<Result<ApiRespuesta>> postMultipart(
    String ruta, {
    required String campo,
    required String nombreDeArchivo,
    required Uint8List bytes,
    Map<String, String>? headers,
    Duration? timeout,
  }) => _conSesion(
    headers,
    (h) => _cliente.postMultipart(
      ruta,
      campo: campo,
      nombreDeArchivo: nombreDeArchivo,
      bytes: bytes,
      headers: h,
      timeout: timeout,
    ),
  );

  /// El camino único de los cinco verbos.
  ///
  /// [enviar] se invoca con los encabezados finales y **puede invocarse dos
  /// veces**. Que eso sea seguro no es casualidad: [ApiClient] compone un
  /// `http.Request` nuevo en cada llamada a partir de la ruta y el objeto JSON, así
  /// que no hay ningún flujo ya consumido que el reintento pudiera encontrar
  /// vacío.
  ///
  /// ⚠️ **Y VALE IGUAL PARA LAS SUBIDAS, que es donde el invariante se podía perder.**
  /// Un `MultipartRequest` con un flujo dentro **no se puede reenviar**: el segundo
  /// intento mandaría un cuerpo vacío y el servidor contestaría «no llegó ningún
  /// archivo» **por un problema de token**. Por eso `postMultipart` recibe **bytes** y
  /// la petición se arma dentro de [ApiClient] en cada llamada. Quien añada otro verbo
  /// con cuerpo tiene que mantener esa propiedad.
  Future<Result<ApiRespuesta>> _conSesion(
    Map<String, String>? headersDelLlamante,
    Future<Result<ApiRespuesta>> Function(Map<String, String> headers) enviar,
  ) async {
    final primerToken = await _gestor.tokenDeAccesoVigente();

    final String token;
    switch (primerToken) {
      case Err<String>(:final failure):
        // Sin sesión no se envía nada. Mandar la petición sin firma sólo para
        // cosechar el 401 gastaría un viaje y, en el grupo de autenticación,
        // cuota del limitador.
        return Result.failure(failure);
      case Ok<String>(:final value):
        token = value;
    }

    final primera = await enviar(_firmar(headersDelLlamante, token));

    final respuesta = switch (primera) {
      Ok<ApiRespuesta>(:final value) => value,
      Err<ApiRespuesta>() => null,
    };

    // Un fallo de transporte se devuelve tal cual: no hubo respuesta, así que no
    // hay nada que indique que el problema sea la sesión.
    if (respuesta == null || respuesta.statusCode != 401) return primera;

    final renovado = await _gestor.renovarTrasRechazo(token);

    switch (renovado) {
      case Err<String>():
        // La renovación no salió. Se devuelve **el 401 original**, y no el fallo
        // de la renovación, para no romper el contrato heredado de `ApiClient`:
        // hubo respuesta del servidor, así que el resultado es una respuesta. El
        // estado de la sesión ya refleja lo que pasó —el gestor lo publicó— y
        // quien lo observe se enterará por ahí.
        return primera;

      case Ok<String>(:final value):
        return enviar(_firmar(headersDelLlamante, value));
    }
  }

  /// Los encabezados del llamante más la firma.
  ///
  /// `Authorization` va **al final**, así que gana sobre cualquiera que viniera
  /// del llamante: la sesión la decide el gestor, no la capa que pide un recurso.
  static Map<String, String> _firmar(
    Map<String, String>? headersDelLlamante,
    String token,
  ) => {...?headersDelLlamante, 'Authorization': 'Bearer $token'};
}
