/// Cuántos accesos del plan se usan, tal como lo devuelve
/// `GET /companies/{id}/access-capacity`.
///
/// **LA CIFRA ES DE TODA LA ORGANIZATION, NO DE ESTA EMPRESA**, y es lo que la hace
/// útil: la bolsa del plan se reparte entre todas las empresas del cliente. Por eso la
/// pantalla la enseña con esas palabras —«en todas tus empresas»— y **separada** del
/// número de personas de la lista. Juntarlas haría creer que los accesos libres son
/// para esta empresa, cuando quizá ya no queda ninguno.
///
/// **NO TRAE EL PLAN NI SU PRECIO**, a propósito: el servidor publica aquí sólo la
/// línea de accesos. Un Maestro administra un equipo, no el contrato.
class CapacidadDeAccesos {
  const CapacidadDeAccesos({
    required this.delPlan,
    required this.adicionales,
    required this.total,
    required this.usados,
    required this.libres,
  });

  factory CapacidadDeAccesos.deJson(Map<String, dynamic> json) =>
      CapacidadDeAccesos(
        delPlan: (json['included'] as num).toInt(),
        adicionales: (json['extra'] as num).toInt(),
        total: (json['total'] as num).toInt(),
        usados: (json['usage'] as num).toInt(),
        libres: (json['remaining'] as num).toInt(),
      );

  /// Los que trae el plan contratado.
  final int delPlan;

  /// Los comprados aparte. **Hoy siempre 0**: el adicional de accesos existe en el
  /// catálogo pero no tiene versión vendible, porque no se le inventó precio. Se lee
  /// de todas formas en vez de darlo por cero, para que el día que se venda la
  /// pantalla ya lo diga.
  final int adicionales;

  /// `delPlan + adicionales`. **Lo calcula el servidor**, y aquí no se recalcula:
  /// dos cuentas del mismo número son dos sitios donde pueden discrepar.
  final int total;

  /// Los que se usan ahora, con la **regla del dueño** ya aplicada —el dueño de la
  /// organización cuenta 1 en total, los demás 1 por empresa—.
  final int usados;

  /// `total - usados`, del servidor. Puede ser 0.
  final int libres;

  /// ¿De dónde sale el total? Sólo tiene sentido enseñarlo si hay adicionales.
  ///
  /// Sin adicionales, «15 del plan + 0 adicionales» es ruido; con ellos, explica un
  /// número que de otro modo no se entiende de dónde viene.
  String? get origenDelTotal => adicionales == 0
      ? null
      : '$delPlan del plan + $adicionales ${adicionales == 1 ? "adicional" : "adicionales"}';
}
