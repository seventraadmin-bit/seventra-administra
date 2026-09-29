import '../error/failure.dart';
import '../error/result.dart';

/// Los tres ayudantes de JSON que el backend SaaS hace falta, y ninguno más.
///
/// DELIBERADAMENTE MÍNIMO Y SIN GENERACIÓN DE CÓDIGO. El proyecto tiene 1394
/// archivos Dart y no usa `json_serializable` ni `freezed` —los `.g.dart` que
/// existen son de Riverpod—, así que introducirlos aquí sería el patrón nuevo más
/// grande de la etapa, con su paso de `build_runner`, a cambio de nada: IF-1 no
/// mapea ni un solo modelo de dominio. Cuando IF-6 tenga que mapear empleados se
/// decidirá con casos reales delante.
///
/// Convenciones del backend, verificadas sobre su código:
///
///  · nombres en `camelCase` (`System.Text.Json` por omisión);
///  · `DateOnly` → `"2026-01-01"`;
///  · `DateTimeOffset` → ISO-8601 con desplazamiento;
///  · `Guid` → cadena canónica;
///  · enumeraciones → **siempre cadena**, nunca ordinal;
///  · nulos presentes como `null`, no omitidos.
class JsonApi {
  const JsonApi._();

  /// Un elemento de una lista JSON, exigiendo que sea objeto.
  ///
  /// Hace falta porque el backend devuelve las dos formas: `GET /companies`
  /// entrega un array desnudo y `GET /employees` un objeto `{items, nextCursor}`.
  static Result<List<Map<String, Object?>>> objetos(List<Object?> lista) {
    final salida = <Map<String, Object?>>[];

    for (final elemento in lista) {
      if (elemento is! Map<String, Object?>) {
        return const Result.failure(
          ApiRespuestaInesperadaFailure(
            'La lista trae un elemento que no es un objeto JSON.',
          ),
        );
      }

      salida.add(elemento);
    }

    return Result.ok(salida);
  }

  /// Una fecha sin hora, como la escribe `DateOnly`.
  ///
  /// Devuelve `null` si el campo venía nulo o ausente, y **lanza sólo si el texto
  /// no es una fecha** — eso sería un desacuerdo de contrato, no un dato
  /// opcional, y hacerlo silencioso escondería un cambio del servidor.
  static DateTime? fecha(Object? valor) {
    if (valor == null) return null;

    if (valor is! String) {
      throw FormatException(
        'Se esperaba una fecha en texto y llegó ${valor.runtimeType}.',
      );
    }

    return DateTime.parse(valor);
  }

  /// Un instante con desplazamiento, como lo escribe `DateTimeOffset`,
  /// normalizado a UTC.
  ///
  /// Se normaliza aquí y no en cada pantalla: dejar el desplazamiento del
  /// servidor circulando por la interfaz haría que dos comparaciones de fechas
  /// dieran resultados distintos según de dónde vinieran.
  static DateTime? instante(Object? valor) {
    final resultado = fecha(valor);

    return resultado?.toUtc();
  }
}
