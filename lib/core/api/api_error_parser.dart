import '../error/failure.dart';
import 'api_respuesta.dart';

/// Convierte una respuesta HTTP no exitosa en un [ApiHttpFailure], sin perder lo
/// que las capas siguientes necesitarán y sin romperse con lo que no reconoce.
///
/// IF-1 NO LO LLAMA POR SU CUENTA: el cliente devuelve la respuesta tal cual, y
/// es el repositorio —o la capa de sesión— quien decide convertirla en fallo.
/// Está aquí para que esa conversión sea una sola, y no una interpretación
/// distinta por módulo.
///
/// ES TOLERANTE EN TRES NIVELES, porque el backend es uniforme salvo en un sitio:
///
///  1. `{code, message}` — lo que devuelve toda denegación del backend, más la
///     variante con `usedBytes`/`capacityBytes` de una respuesta de capacidad.
///  2. JSON con otra forma — se conserva de manera ACOTADA, sin inventar un
///     `code` que el servidor no envió.
///  3. Cuerpo no-JSON o vacío — el **429** lo produce el limitador de ASP.NET y
///     no sigue el contrato; un 502 de un proxy puede llegar como HTML. Ninguno
///     de los dos debe romper el parser.
class ApiErrorParser {
  const ApiErrorParser._();

  /// Cuántos caracteres del cuerpo se conservan cuando no se reconoce su forma.
  ///
  /// Suficiente para diagnosticar y lejos de volcar una página entera: este texto
  /// termina en pantallas y en registros, y el cuerpo de un error de proxy puede
  /// describir la red interna.
  static const int _maxDiagnostico = 200;

  /// Las claves que se conservan de un cuerpo con forma desconocida.
  ///
  /// LISTA BLANCA, no lista negra, por la misma razón que `AuditPayload` en el
  /// backend: copiar todo el cuerpo «porque puede servir» es cómo un dato
  /// sensible acaba en un registro que nadie limpia.
  static const Set<String> _clavesUtiles = {'usedBytes', 'capacityBytes'};

  static ApiHttpFailure interpretar(ApiRespuesta respuesta) {
    final decodificado = respuesta.decodificar().when(
      ok: (valor) => valor,
      failure: (_) => null,
    );

    if (decodificado is Map<String, Object?>) {
      final codigo = _texto(decodificado['code']);
      final mensaje = _texto(decodificado['message']);

      if (codigo != null || mensaje != null) {
        return ApiHttpFailure(
          statusCode: respuesta.statusCode,
          codigo: codigo,
          message: mensaje ?? _generico(respuesta.statusCode),
          extra: {
            for (final clave in _clavesUtiles)
              if (decodificado[clave] != null) clave: decodificado[clave],
          },
        );
      }

      // JSON válido con otra forma: se dice qué claves traía, no qué valores.
      // Basta para diagnosticar un desacuerdo de contrato sin volcar datos.
      return ApiHttpFailure(
        statusCode: respuesta.statusCode,
        message:
            '${_generico(respuesta.statusCode)} '
            '(respuesta con campos: ${decodificado.keys.take(8).join(', ')})',
      );
    }

    // Ni objeto JSON: el 429 del limitador, un HTML de proxy, un cuerpo vacío.
    final recorte = respuesta.cuerpo.trim();

    return ApiHttpFailure(
      statusCode: respuesta.statusCode,
      message:
          recorte.isEmpty
              ? _generico(respuesta.statusCode)
              : '${_generico(respuesta.statusCode)} '
                  '(${recorte.length > _maxDiagnostico ? '${recorte.substring(0, _maxDiagnostico)}…' : recorte})',
    );
  }

  static String? _texto(Object? valor) {
    if (valor is! String) return null;

    final limpio = valor.trim();
    return limpio.isEmpty ? null : limpio;
  }

  /// Un mensaje por familia de status, para cuando el servidor no manda uno.
  ///
  /// Sin interpretar nada: decir «sesión expirada» ante un 401 sería la decisión
  /// de IF-2, y tomarla aquí la escondería en el transporte.
  static String _generico(int statusCode) => switch (statusCode) {
    400 => 'La solicitud no es válida.',
    401 => 'La sesión no es válida o expiró.',
    402 => 'La suscripción no permite esta operación.',
    403 => 'No tienes autoridad para esta operación.',
    404 => 'No se encontró lo solicitado.',
    409 => 'El estado actual no permite esta operación.',
    413 => 'El archivo es demasiado grande.',
    415 => 'El tipo de archivo no se acepta.',
    422 => 'El contenido no se puede utilizar.',
    429 => 'Demasiadas solicitudes. Inténtalo en un momento.',
    >= 500 => 'El servidor tuvo un problema.',
    _ => 'La solicitud no se pudo completar (HTTP $statusCode).',
  };
}
