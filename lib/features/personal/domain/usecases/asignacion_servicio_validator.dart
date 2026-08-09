/// Validaciones de fecha puras de `AsignacionServicio` (Etapa 5D) —
/// deliberadamente separado de `EmpleadoValidator`: esta entidad no es
/// propiedad exclusiva de Empleado (ver el doc comment de
/// `AsignacionServicio`).
class AsignacionServicioValidator {
  const AsignacionServicioValidator();

  /// La fecha de inicio de una asignación no puede ser anterior a la
  /// fecha de ingreso del periodo laboral vigente del Empleado (no se
  /// puede estar asignado a un Servicio antes de haber sido contratado),
  /// ni futura.
  bool fechaInicioValida(DateTime fechaInicio, DateTime fechaIngresoEmpleado, {DateTime? hoy}) {
    final referencia = hoy ?? DateTime.now();
    if (fechaInicio.isAfter(referencia)) return false;
    return !fechaInicio.isBefore(fechaIngresoEmpleado);
  }

  /// La fecha de término no puede ser anterior al inicio de la
  /// asignación que cierra, ni futura.
  bool fechaTerminoValida(DateTime fechaTermino, DateTime fechaInicioVigente, {DateTime? hoy}) {
    final referencia = hoy ?? DateTime.now();
    if (fechaTermino.isAfter(referencia)) return false;
    return !fechaTermino.isBefore(fechaInicioVigente);
  }
}
