import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../organizacion/data/tables/servicio_table.dart';
import '../../../personal/data/tables/empleado_table.dart';
import 'vehiculo_table.dart';

/// Motivo de término de una [AsignacionVehiculo] (Etapa 8B) — enum
/// enriquecido, mismo criterio que `MotivoTerminoAsignacion` (Personal
/// 5D) y `MotivoBajaEmpleado`: la propiedad vive en cada valor, no en
/// una lista aparte.
enum MotivoTerminoAsignacionVehiculo {
  cambioResponsable(seleccionableManualmente: false),
  liberacion(seleccionableManualmente: true),

  /// Automático — lo coloca `VehiculoRepositoryImpl.darDeBaja` al
  /// cerrar la asignación vigente en la misma transacción que la baja
  /// del vehículo (mismo criterio que `MotivoTerminoAsignacion.bajaEmpleado`
  /// en 5D: "no quiero que pueda quedar Vehiculo = Baja, Asignación =
  /// Todavía vigente").
  bajaVehiculo(seleccionableManualmente: false),
  otro(seleccionableManualmente: true, requiereObservaciones: true);

  const MotivoTerminoAsignacionVehiculo({required this.seleccionableManualmente, this.requiereObservaciones = false});

  final bool seleccionableManualmente;
  final bool requiereObservaciones;
}

/// Asignación administrativa de un Vehículo a un Empleado o a un
/// Servicio (Etapa 8B) — la única fuente de verdad de "quién lo tiene"
/// y "quién lo ha tenido antes". Ni `Vehiculo` ni `Empleado`/`Servicio`
/// ganan columnas nuevas: ninguno de los tres "posee" la asignación,
/// todos la consultan (mismo principio explícito de `AsignacionServicio`,
/// Etapa 5D: "no duplicar datos del empleado dentro del servicio ni
/// viceversa").
///
/// Tabla híbrida — toma la forma de FK de `Asignacion` (Inventario,
/// Etapa 7B: `empleadoId`/`servicioId` nullable + `CHECK` exactamente-
/// uno, porque un Vehículo también puede ir a un Empleado o a un
/// Servicio) y la forma de cierre de `AsignacionServicio` (Personal,
/// Etapa 5D: `fechaTermino IS NULL` = vigente, sin columna `estatus`
/// separada, porque un Vehículo no tiene el concepto de "dañado/
/// perdido" que sí tiene un bien de Inventario). Ver el plan técnico
/// completo de Vehículos (§1.3) para el razonamiento comparado de
/// ambos precedentes.
///
/// `observaciones` se captura al asignar; `observacionesTermino` al
/// cerrar — son momentos distintos, nunca el mismo campo.
///
/// Refuerzo a nivel de BD de "un Vehículo solo puede tener una
/// asignación vigente a la vez" — mismo mecanismo de índice único
/// parcial ya usado en `idx_asignacion_servicio_empleado_activa`
/// e `idx_asignacion_unidad_activa`. La protección de dominio vive en
/// `AsignarVehiculoUseCase`/`CambiarAsignacionVehiculoUseCase`.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_asignacion_vehiculo_vigente '
  'ON asignacion_vehiculo (vehiculo_id) WHERE fecha_termino IS NULL',
)
class AsignacionVehiculo extends Table with AuditColumns {
  TextColumn get vehiculoId => text().references(Vehiculo, #id, onDelete: KeyAction.restrict)();

  TextColumn get empleadoId => text().nullable().references(Empleado, #id, onDelete: KeyAction.restrict)();

  TextColumn get servicioId => text().nullable().references(Servicio, #id, onDelete: KeyAction.restrict)();

  DateTimeColumn get fechaInicio => dateTime()();

  DateTimeColumn get fechaTermino => dateTime().nullable()();

  TextColumn get motivoTermino => text().nullable()();

  TextColumn get observaciones => text().nullable()();

  TextColumn get observacionesTermino => text().nullable()();

  @override
  List<String> get customConstraints => [
        'CHECK ((empleado_id IS NOT NULL AND servicio_id IS NULL) OR '
            '(empleado_id IS NULL AND servicio_id IS NOT NULL))',
        'CHECK (fecha_termino IS NULL OR fecha_termino >= fecha_inicio)',
      ];
}
