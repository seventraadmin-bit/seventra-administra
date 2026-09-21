import '../../../../core/database/seed/seed_ids.dart';
import '../../../../core/validation/codigo_postal_fiscal_validator.dart';
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

  /// Formato únicamente — mismo criterio que `curpValido`/`rfcValido`.
  bool codigoPostalFiscalValido(String codigoPostal) => CodigoPostalFiscalValidator.esFormatoValido(codigoPostal);

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

  /// La fecha de baja no puede ser anterior al inicio del periodo
  /// laboral vigente que está cerrando, ni futura (Etapa 5C).
  bool fechaBajaValida(DateTime fechaBaja, DateTime fechaIngresoVigente, {DateTime? hoy}) {
    final referencia = hoy ?? DateTime.now();
    if (fechaBaja.isAfter(referencia)) return false;
    return !fechaBaja.isBefore(fechaIngresoVigente);
  }

  /// La fecha del nuevo periodo (Reingreso, Etapa 5C) debe cumplir las
  /// mismas reglas que cualquier fecha de ingreso, y además no puede
  /// ser anterior a la baja del periodo anterior que se está cerrando.
  bool fechaReingresoValida(
    DateTime fechaIngreso,
    DateTime fechaNacimiento,
    DateTime? fechaBajaAnterior, {
    DateTime? hoy,
  }) {
    if (!fechaIngresoValida(fechaIngreso, fechaNacimiento, hoy: hoy)) return false;
    if (fechaBajaAnterior == null) return true;
    return !fechaIngreso.isBefore(fechaBajaAnterior);
  }

  /// Datos bancarios (Etapa 6A) — el bloque completo es opcional; si se
  /// captura algo, `bancoId` es obligatorio y se necesita al menos uno
  /// de `numeroCuentaTarjeta`/`clabe` (Resolución explícita de Marlon:
  /// nunca exigir ambos a la vez).
  bool datosBancariosValidos({String? bancoId, String? numeroCuentaTarjeta, String? clabe}) {
    final tarjeta = numeroCuentaTarjeta?.trim();
    final clabeLimpia = clabe?.trim();
    final tieneAlgo = bancoId != null || (tarjeta?.isNotEmpty ?? false) || (clabeLimpia?.isNotEmpty ?? false);
    if (!tieneAlgo) return true;
    if (bancoId == null) return false;
    return (tarjeta?.isNotEmpty ?? false) || (clabeLimpia?.isNotEmpty ?? false);
  }

  /// Cuando `bancoId` apunta a la fila catálogo `'OTRO'` (Etapa 15), es
  /// obligatorio capturar cuál banco es en realidad — de lo contrario
  /// "Otro" queda como un banco definitivo sin especificar, que es
  /// exactamente el hueco que esta regla cierra. Para cualquier otro
  /// banco (o sin banco capturado), el campo es irrelevante.
  bool bancoOtroDescripcionValida({String? bancoId, String? bancoOtroDescripcion}) {
    if (bancoId != SeedIds.bancoOtro) return true;
    return (bancoOtroDescripcion?.trim().isNotEmpty ?? false);
  }

  /// Condición laboral administrativa (Etapa 6A) — solo relevante para
  /// empleados sin `AsignacionServicio`. `> 0` cuando se captura,
  /// nunca `0` (Resolución explícita de Marlon).
  bool sueldoAdministrativoValido(int? sueldoMensualAdministrativo) {
    return sueldoMensualAdministrativo == null || sueldoMensualAdministrativo > 0;
  }

  /// A diferencia del sueldo, el bono administrativo sí acepta `0`
  /// (Resolución explícita de Marlon: "existen personas/servicios sin
  /// bono").
  bool bonoAdministrativoValido(int? bonoMensualAdministrativo) {
    return bonoMensualAdministrativo == null || bonoMensualAdministrativo >= 0;
  }
}
