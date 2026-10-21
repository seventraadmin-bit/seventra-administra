import 'dart:convert';
import 'dart:typed_data';

import '../error/failure.dart';
import '../error/result.dart';

/// Una respuesta HTTP tal cual llegó. Es infraestructura: no sabe nada de
/// dominio y no decide nada.
///
/// EXISTE UNA RESPUESTA AUNQUE EL STATUS NO SEA 2xx. Un 404, un 409 o un 500 son
/// respuestas legítimas que quien llamó debe interpretar —en Contratos, un 409
/// `contrato_con_sucesor` es información de negocio—, así que el cliente HTTP no
/// lanza por ellas. Lo que sí produce un fallo es que NO haya respuesta: sin red,
/// timeout o transporte roto.
class ApiRespuesta {
  const ApiRespuesta({
    required this.statusCode,
    required this.headers,
    required this.cuerpo,
    this.bytes,
  });

  final int statusCode;
  final Map<String, String> headers;

  /// El cuerpo crudo. Se conserva para diagnóstico y para que el parser de
  /// errores pueda trabajar con lo que realmente llegó, incluido HTML de un proxy.
  final String cuerpo;

  /// Los bytes **tal como llegaron**, y **sólo cuando se pidieron**.
  ///
  /// ⚠️ **HACE FALTA PORQUE [cuerpo] NO SIRVE PARA UN BINARIO.** Decodificar un PNG
  /// como cadena no lo deja «un poco mal»: los bytes que salen **ya no son los que
  /// entraron**, porque toda secuencia que no sea UTF-8 válido se sustituye por el
  /// carácter de reemplazo. Un logotipo que viajara por `cuerpo` llegaría corrupto y
  /// nada fallaría en el camino.
  ///
  /// **Nulo salvo que quien llama use `getBytes`.** Guardarlos siempre duplicaría en
  /// memoria **cada** respuesta JSON del producto, y son miles por sesión; aquí se paga
  /// sólo donde hace falta.
  final Uint8List? bytes;

  bool get esExitosa => statusCode >= 200 && statusCode < 300;

  /// Decodifica el cuerpo como JSON.
  ///
  /// ES UNA OPERACIÓN EXPLÍCITA Y NO UN GETTER, y la diferencia importa: un
  /// `Object? get json` parece inofensivo en el punto de llamada y puede lanzar
  /// `FormatException` sin que nada en su forma lo anuncie. Basta un proxy que
  /// devuelva HTML para que una pantalla reviente con un error que no se parece a
  /// su causa.
  ///
  /// Así que devuelve [Result]: un cuerpo ilegible es un
  /// [ApiJsonInvalidoFailure], nunca una excepción que escape.
  ///
  /// Un cuerpo VACÍO decodifica a `null` sin error — es lo que devuelve un 204, y
  /// tratarlo como JSON roto sería confundir «no hay contenido» con «el contenido
  /// está mal».
  Result<Object?> decodificar() {
    if (cuerpo.trim().isEmpty) return const Result.ok(null);

    try {
      return Result.ok(jsonDecode(cuerpo));
    } on FormatException {
      // El mensaje NO lleva el cuerpo: podría ser una página de error de un
      // proxy corporativo con información de la red interna, y este texto acaba
      // en pantallas y en registros.
      return Result.failure(
        ApiJsonInvalidoFailure(
          'La respuesta del servidor no es JSON válido (HTTP $statusCode).',
        ),
      );
    }
  }

  /// El cuerpo como objeto JSON. Una lista o un número producen
  /// [ApiRespuestaInesperadaFailure], que es un desacuerdo de contrato y no un
  /// JSON roto.
  Result<Map<String, Object?>> comoObjeto() => decodificar().when(
    ok:
        (valor) =>
            valor is Map<String, Object?>
                ? Result.ok(valor)
                : Result.failure(
                  ApiRespuestaInesperadaFailure(
                    'Se esperaba un objeto JSON y llegó ${_nombreDe(valor)} (HTTP $statusCode).',
                  ),
                ),
    failure: Result.failure,
  );

  /// El cuerpo como lista JSON.
  ///
  /// Hace falta porque el backend devuelve las dos formas: `GET /companies`
  /// entrega un array desnudo y `GET /employees` un objeto `{items, nextCursor}`.
  /// Suponer un envoltorio único habría obligado a envolver a mano la mitad de
  /// las respuestas.
  Result<List<Object?>> comoLista() => decodificar().when(
    ok:
        (valor) =>
            valor is List<Object?>
                ? Result.ok(valor)
                : Result.failure(
                  ApiRespuestaInesperadaFailure(
                    'Se esperaba una lista JSON y llegó ${_nombreDe(valor)} (HTTP $statusCode).',
                  ),
                ),
    failure: Result.failure,
  );

  /// Describe el tipo recibido SIN incluir su contenido: el mensaje viaja a la
  /// pantalla y a los registros.
  static String _nombreDe(Object? valor) => switch (valor) {
    null => 'un cuerpo vacío',
    List<Object?>() => 'una lista',
    Map<Object?, Object?>() => 'un objeto',
    String() => 'texto',
    num() => 'un número',
    bool() => 'un booleano',
    _ => 'otro tipo',
  };

  @override
  String toString() => 'ApiRespuesta($statusCode, ${cuerpo.length} bytes)';
}
