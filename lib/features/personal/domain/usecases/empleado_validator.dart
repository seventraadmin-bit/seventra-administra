import 'calcular_edad.dart';

/// Validaciones de formato puras del expediente del Empleado (Etapa
/// 5A) — solo longitud/patrón, **nunca** verificación contra una
/// autoridad externa (SAT/IMSS/RENAPO): no existe esa integración en
/// este alcance, y acoplarse a la validación exacta del organismo
/// emisor es exactamente el error que ya se evitó con el UUID de
/// `ComplementoPago` en la Etapa 4J.3 — mismo principio aquí.
class EmpleadoValidator {
  const EmpleadoValidator();

  static final _curpPattern = RegExp(r'^[A-Za-z0-9]{18}$');
  static final _rfcPattern = RegExp(r'^[A-Za-z0-9]{12,13}$');
  static final _nssPattern = RegExp(r'^[0-9]{11}$');

  bool curpValido(String curp) => _curpPattern.hasMatch(curp.trim());

  bool rfcValido(String rfc) => _rfcPattern.hasMatch(rfc.trim());

  bool nssValido(String nss) => _nssPattern.hasMatch(nss.trim());

  /// Rechaza fechas de nacimiento futuras y edades irreales (< 15 años)
  /// — regla mínima de sanidad, no una regla laboral completa.
  bool fechaNacimientoValida(DateTime fechaNacimiento, {DateTime? hoy}) {
    final referencia = hoy ?? DateTime.now();
    if (fechaNacimiento.isAfter(referencia)) return false;
    return calcularEdad(fechaNacimiento, hoy: referencia) >= 15;
  }

  /// La fecha de ingreso no puede ser anterior a que el Empleado
  /// cumpliera la edad mínima laboral, ni futura.
  bool fechaIngresoValida(DateTime fechaIngreso, DateTime fechaNacimiento, {DateTime? hoy}) {
    final referencia = hoy ?? DateTime.now();
    if (fechaIngreso.isAfter(referencia)) return false;
    final edadAlIngresar = calcularEdad(fechaNacimiento, hoy: fechaIngreso);
    return edadAlIngresar >= 15;
  }

  /// Regla mínima compartida por las 3 fechas de evaluación (Perfil
  /// psicológico, Estudio socioeconómico, Antidoping, Etapa 5B): nunca
  /// futuras. Sin reglas de vigencia/vencimiento — fuera de alcance
  /// explícito de esta etapa.
  bool fechaEvaluacionValida(DateTime fecha, {DateTime? hoy}) {
    return !fecha.isAfter(hoy ?? DateTime.now());
  }
}
