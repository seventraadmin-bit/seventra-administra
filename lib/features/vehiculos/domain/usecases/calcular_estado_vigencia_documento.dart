/// Estado de vigencia de un `VehiculoDocumento` (Etapa 8C) —
/// deliberadamente derivado, nunca almacenado (mismo criterio que
/// `calcularEdad`/`calcularCicloLaboralEmpleado`).
enum EstadoVigenciaDocumento { sinVencimiento, vigente, proximoAVencer, vencido }

/// Umbral de "próximo a vencer" — 30 días, confirmado explícitamente
/// por Marlon como punto de partida razonable. Único punto de verdad:
/// una constante nombrada, no repetida en cada llamador, para que una
/// futura pantalla de Configuración pueda sobreescribirla sin migración
/// ni refactor (no existe módulo de Configuración todavía, así que no
/// se construye esa tabla por anticipado).
const umbralDiasProximoAVencerDocumento = 30;

/// `fechaVencimiento == null` → `sinVencimiento` (ej. una factura no
/// vence). `hoy` es inyectable para pruebas — mismo patrón que
/// `calcularEdad`.
EstadoVigenciaDocumento calcularEstadoVigenciaDocumento(
  DateTime? fechaVencimiento, {
  DateTime? hoy,
  int umbralDias = umbralDiasProximoAVencerDocumento,
}) {
  if (fechaVencimiento == null) return EstadoVigenciaDocumento.sinVencimiento;

  final referencia = hoy ?? DateTime.now();
  final hoySoloFecha = DateTime(referencia.year, referencia.month, referencia.day);
  final vencimientoSoloFecha = DateTime(fechaVencimiento.year, fechaVencimiento.month, fechaVencimiento.day);

  if (vencimientoSoloFecha.isBefore(hoySoloFecha)) return EstadoVigenciaDocumento.vencido;

  final limiteProximoAVencer = hoySoloFecha.add(Duration(days: umbralDias));
  if (!vencimientoSoloFecha.isAfter(limiteProximoAVencer)) return EstadoVigenciaDocumento.proximoAVencer;

  return EstadoVigenciaDocumento.vigente;
}
