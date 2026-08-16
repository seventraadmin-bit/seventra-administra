import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_con_vigencia.dart';

/// Resultado de resolver a qué línea comercial pertenece una
/// asignación nueva (Etapa 15, rediseño de "Condiciones de Personal") —
/// compartido por `AsignarEmpleadoServicioUseCase`,
/// `CambiarServicioEmpleadoUseCase` y `CrearEmpleadoUseCase`, cada uno
/// lo traduce a su propio resultado nombrado.
sealed class ResolucionLineaComercialAsignacion {}

class ResolucionLineaComercialExitosa extends ResolucionLineaComercialAsignacion {
  ResolucionLineaComercialExitosa({this.linea, this.sueldoResuelto, required this.bonoResuelto});

  /// `null` solo si el Servicio no tiene ninguna línea comercial vigente
  /// (nada que elegir) — nunca si tiene alguna y no se eligió.
  final LineaComercialConVigencia? linea;
  final int? sueldoResuelto;
  final int bonoResuelto;
}

/// El Servicio tiene al menos una línea comercial vigente y no se
/// eligió ninguna — ya no existe la opción de "asignar genérico"
/// perdiendo esa relación (Resolución explícita de Marlon).
class ResolucionLineaComercialRequerida extends ResolucionLineaComercialAsignacion {}

/// La línea elegida no pertenece al Servicio, o no tiene una vigencia
/// vigente hoy.
class ResolucionLineaComercialInvalida extends ResolucionLineaComercialAsignacion {}

/// Resuelve la línea comercial de una asignación y, desde ahí, el
/// sueldo/bono precargado (Etapa 15) — reemplaza el fallback a
/// `Servicio.sueldoMensualReferenciaPersonal`/`bonoMensualReferenciaPersonal`
/// (retirado de la captura nueva, columnas conservadas solo por
/// compatibilidad con datos históricos). `sueldoMensual`/`bonoMensual`
/// siguen siendo la excepción individual: si se capturan, ganan sobre
/// la referencia de la línea.
ResolucionLineaComercialAsignacion resolverLineaComercialAsignacion({
  required List<LineaComercialConVigencia> lineasDelServicio,
  required String? lineaComercialId,
  int? sueldoMensual,
  int? bonoMensual,
}) {
  final lineasVigentes = lineasDelServicio.where((l) => l.vigenciaActual != null).toList();

  LineaComercialConVigencia? lineaElegida;
  if (lineaComercialId != null) {
    for (final l in lineasVigentes) {
      if (l.linea.id == lineaComercialId) {
        lineaElegida = l;
        break;
      }
    }
    if (lineaElegida == null) return ResolucionLineaComercialInvalida();
  } else if (lineasVigentes.isNotEmpty) {
    return ResolucionLineaComercialRequerida();
  }

  return ResolucionLineaComercialExitosa(
    linea: lineaElegida,
    sueldoResuelto: sueldoMensual ?? lineaElegida?.vigenciaActual?.sueldoMensualReferenciaPersonal,
    bonoResuelto: bonoMensual ?? lineaElegida?.vigenciaActual?.bonoMensualReferenciaPersonal ?? 0,
  );
}

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
