/// Edad en años cumplidos a partir de una fecha de nacimiento — nunca
/// se almacena (mismo criterio que `estaVencida`/
/// `calcularRangoAntiguedad` en Finanzas): siempre se deriva en el
/// momento de la consulta.
int calcularEdad(DateTime fechaNacimiento, {DateTime? hoy}) {
  final referencia = hoy ?? DateTime.now();
  var edad = referencia.year - fechaNacimiento.year;
  final aunNoCumpleAnios = referencia.month < fechaNacimiento.month ||
      (referencia.month == fechaNacimiento.month && referencia.day < fechaNacimiento.day);
  if (aunNoCumpleAnios) edad--;
  return edad;
}
