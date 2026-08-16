import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../../core/database/tables/catalogos_tables.dart';
import '../../../organizacion/data/tables/servicio_linea_comercial_table.dart';
import '../../../organizacion/data/tables/servicio_table.dart';
import 'empleado_table.dart';

/// Motivo de término de una [AsignacionServicio] (Etapa 5D) — enum
/// enriquecido, mismo criterio que `MotivoBajaEmpleado` (Etapa 5C):
/// `seleccionableManualmente`/`requiereObservaciones` viven como
/// propiedad de cada valor, no como una lista aparte. Los 3 motivos
/// automáticos (`cambioServicio`, `bajaEmpleado`, `servicioTerminado`)
/// los coloca el sistema — nunca aparecen en el selector manual del
/// diálogo de Retiro (Resolución explícita de Marlon, Etapa 5D).
enum MotivoTerminoAsignacion {
  solicitudCliente(seleccionableManualmente: true),
  reestructuracionOperativa(seleccionableManualmente: true),
  bajoDesempeno(seleccionableManualmente: true),
  otro(seleccionableManualmente: true, requiereObservaciones: true),

  /// Automático — lo coloca `CambiarServicioEmpleadoUseCase`.
  cambioServicio(seleccionableManualmente: false),

  /// Automático — lo coloca `EmpleadoRepositoryImpl.registrarBajaLaboral`
  /// al cerrar la asignación vigente en la misma transacción que la
  /// Baja laboral (Etapa 5C + 5D, Resolución explícita de Marlon: "no
  /// quiero que pueda quedar Empleado = Baja, Servicio = Todavía
  /// asignado").
  bajaEmpleado(seleccionableManualmente: false),

  /// Automático — lo coloca `ServicioRepositoryImpl.cambiarEstatus` al
  /// cerrar todas las asignaciones vigentes de un Servicio que pasa a
  /// `terminado`, en la misma transacción.
  servicioTerminado(seleccionableManualmente: false);

  const MotivoTerminoAsignacion({required this.seleccionableManualmente, this.requiereObservaciones = false});

  final bool seleccionableManualmente;
  final bool requiereObservaciones;
}

/// Asignación administrativa de un Empleado a un Servicio (Etapa 5D) —
/// la única fuente de verdad de "dónde está asignado" y "dónde estuvo
/// antes". Ni `Empleado` ni `Servicio` ganan columnas nuevas: ninguno
/// de los dos "posee" la asignación, ambos la consultan (Resolución
/// explícita de Marlon: "no duplicar datos del empleado dentro del
/// servicio ni datos del servicio dentro del empleado").
///
/// `fechaTermino == null` significa vigente. A diferencia del modelo de
/// periodos laborales de la Etapa 5C (donde solo `Empleado` necesitaba
/// conocer su propio periodo), aquí **dos** dueños distintos consultan
/// esta tabla — Empleado (su asignación actual + su historial) y
/// Servicio (su personal actual + quién ha pasado por él) — por eso es
/// una tabla relacional completa (mismo patrón que
/// `ServicioLineaComercialVigencia`), no un "vigente en el padre +
/// historial aparte".
///
/// `observaciones` se captura al asignar; `observacionesTermino` al
/// cerrar — son momentos distintos, nunca el mismo campo.
///
/// Esta tabla no calcula días laborados, asistencia ni nada relativo a
/// Nómina/PCR — solo el rango administrativo de fechas (Resolución
/// explícita de Marlon, Etapa 5D, punto 8).
///
/// Refuerzo a nivel de BD de "un Empleado solo puede tener una
/// asignación vigente a la vez" (Resolución explícita de Marlon:
/// "Quiero protección tanto en dominio como en base de datos") — mismo
/// mecanismo de índice único parcial ya usado en
/// `idx_contacto_cliente_tipo_principal_activo`. La protección de
/// dominio vive en `AsignarEmpleadoServicioUseCase`/
/// `CambiarServicioEmpleadoUseCase`.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_asignacion_servicio_empleado_activa '
  'ON asignacion_servicio (empleado_id) WHERE fecha_termino IS NULL',
)
class AsignacionServicio extends Table with AuditColumns {
  TextColumn get empleadoId => text().references(Empleado, #id, onDelete: KeyAction.restrict)();

  TextColumn get servicioId => text().references(Servicio, #id, onDelete: KeyAction.restrict)();

  /// Turno de esta asignación — reutiliza el catálogo de modalidades de
  /// turno ya existente (`TipoModalidadTurno`, Etapa 4G.1, usado hoy por
  /// `ServicioLineaComercialVigencia.modalidadTurnoId`): es el mismo
  /// concepto real, evita duplicar catálogo. Vive aquí y no en
  /// `Empleado` porque cambia cuando el Empleado cambia de Servicio.
  TextColumn get turnoId => text().nullable().references(TipoModalidadTurno, #id, onDelete: KeyAction.restrict)();

  /// A qué perfil/línea comercial contratado pertenece esta asignación
  /// (Etapa 15, rediseño de "Condiciones de Personal") — nullable solo
  /// por compatibilidad con asignaciones históricas (nunca se adivina
  /// retroactivamente, Resolución explícita de Marlon); en la captura
  /// nueva, la UI la exige en cuanto el Servicio tiene alguna línea
  /// comercial vigente (`AsignacionServicioValidator.lineaRequerida`) —
  /// nunca vuelve a existir la opción de asignar "genérico" perdiendo
  /// esta relación. De aquí se precargan
  /// `ServicioLineaComercialVigencia.sueldoMensualReferenciaPersonal`/
  /// `bonoMensualReferenciaPersonal` (reemplaza el sueldo global de
  /// `Servicio`, retirado de la captura nueva).
  TextColumn get lineaComercialId =>
      text().nullable().references(ServicioLineaComercial, #id, onDelete: KeyAction.restrict)();

  DateTimeColumn get fechaInicio => dateTime()();

  DateTimeColumn get fechaTermino => dateTime().nullable()();

  TextColumn get motivoTermino => text().nullable()();

  TextColumn get observaciones => text().nullable()();

  TextColumn get observacionesTermino => text().nullable()();

  @override
  List<String> get customConstraints => ['CHECK (fecha_termino IS NULL OR fecha_termino >= fecha_inicio)'];
}
