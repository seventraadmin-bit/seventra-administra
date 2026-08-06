/// Redondeo a centavo más cercano, aritmético — un valor de medio
/// centavo se aleja de cero (Etapa 4I.1, criterio explícito de Marlon):
/// `1.5 → 2`, `-1.5 → -2`. Deliberadamente no se usa `double.round()` de
/// Dart directo — su comportamiento en el punto medio no está
/// documentado como "aleja de cero" de forma explícita, y esta regla de
/// negocio necesita un criterio propio, verificado por prueba.
int redondearCentavos(double valor) {
  return valor >= 0 ? (valor + 0.5).floor() : (valor - 0.5).ceil();
}

/// Importe proporcional de una línea comercial para un periodo — una
/// sola operación antes de redondear (Etapa 4I.1, corrección explícita
/// de Marlon): `precioUnitario × diasAplicables × cantidad / 30`, nunca
/// `precioUnitario / 30` primero (perdería precisión). El redondeo se
/// aplica una vez, al final, por línea — nunca se sub-redondea a mitad
/// de la fórmula.
///
/// La base fija de 30 días (nunca los días reales del mes) es la
/// convención contable ya aprobada para RISEG — un periodo de 31 días
/// (ej. Sportium, 21 jul-20 ago) genuinamente cobra un poco más que un
/// mes de 28.
int calcularImporteProporcional({
  required int precioUnitarioCentavos,
  required int diasAplicables,
  required int cantidadElementos,
}) {
  final valor = precioUnitarioCentavos * diasAplicables * cantidadElementos / 30;
  return redondearCentavos(valor);
}
