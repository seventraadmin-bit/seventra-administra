/// Formato de moneda en pesos mexicanos a partir de centavos, sin
/// depender de Flutter/`intl` en la capa de dominio — mismo criterio
/// ya usado por los renderers de PDF de Reportes (Etapa 12D).
String formatoMonedaNotificacion(int centavos) {
  final pesos = centavos / 100;
  final parteEntera = pesos.truncate().toString();
  final parteDecimal = ((pesos - pesos.truncate()) * 100).round().toString().padLeft(2, '0');

  final buffer = StringBuffer();
  for (var i = 0; i < parteEntera.length; i++) {
    if (i > 0 && (parteEntera.length - i) % 3 == 0) buffer.write(',');
    buffer.write(parteEntera[i]);
  }

  return '\$$buffer.$parteDecimal';
}
