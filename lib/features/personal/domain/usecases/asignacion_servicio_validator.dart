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

  /// Sueldo de una vigencia de `AsignacionServicioSueldoVigencia` (Etapa
  /// 6B) — debe ser `> 0`, mismo criterio que
  /// `Servicio.sueldoMensualReferenciaPersonal`/
  /// `Empleado.sueldoMensualAdministrativo`.
  bool sueldoValido(int sueldoMensual) => sueldoMensual > 0;

  /// A diferencia del sueldo, el bono sí acepta `0`.
  bool bonoValido(int bonoMensual) => bonoMensual >= 0;

  /// La fecha de inicio de una nueva vigencia de sueldo no puede ser
  /// anterior al inicio de la propia asignación que la contiene — no
  /// puede haber un sueldo vigente antes de que la persona estuviera
  /// asignada a ese Servicio. A diferencia de `fechaInicioValida`, sí
  /// admite fechas futuras (Resolución explícita de Marlon: "Debe ser
  /// posible programar una vigencia futura").
  bool fechaVigenciaSueldoValida(DateTime fechaInicioVigencia, DateTime fechaInicioAsignacion) {
    return !fechaInicioVigencia.isBefore(fechaInicioAsignacion);
  }
}
