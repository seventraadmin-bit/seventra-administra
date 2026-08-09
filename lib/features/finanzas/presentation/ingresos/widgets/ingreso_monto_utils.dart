/// Convierte texto capturado en pesos (ej. "1500.50") a centavos —
/// misma unidad que el resto del proyecto. `null` si el texto no es
/// un número válido. Mismo criterio que
/// `registrar_pago_aplicado_dialog.dart`.
int? centavosDesdeTexto(String texto) {
  final normalizado = texto.trim().replaceAll(',', '');
  if (normalizado.isEmpty) return null;
  final pesos = double.tryParse(normalizado);
  if (pesos == null) return null;
  return (pesos * 100).round();
}
