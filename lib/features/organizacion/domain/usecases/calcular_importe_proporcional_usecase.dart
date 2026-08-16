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
/// La base fija de 30 días es la convención contable de RISEG: un mes
/// comercial completo siempre vale 30, sin importar si el calendario
/// real tiene 28, 29, 30 o 31 días (Etapa 15, corrección explícita de
/// Marlon — un periodo de 31 días NO cobra más que uno de 28).
/// `diasAplicables` solo se aparta de 30 cuando el periodo es
/// genuinamente parcial (la vigencia de la línea comercial cambió a
/// mitad de mes) — ver `_calcularDiasAplicables` en
/// `ensamblar_documento_por_emitir_usecase.dart`, la única fuente real
/// de este valor.
int calcularImporteProporcional({
  required int precioUnitarioCentavos,
  required int diasAplicables,
  required int cantidadElementos,
}) {
  final valor = precioUnitarioCentavos * diasAplicables * cantidadElementos / 30;
  return redondearCentavos(valor);
}
