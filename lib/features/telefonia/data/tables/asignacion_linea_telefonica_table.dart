import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../organizacion/data/tables/servicio_table.dart';
import '../../../personal/data/tables/empleado_table.dart';
import '../../../usuarios/data/tables/usuario_table.dart';
import 'linea_telefonica_table.dart';

/// Motivo de término de una [AsignacionLineaTelefonica] (Etapa 9B) —
/// enum enriquecido, mismo mecanismo que
/// `MotivoTerminoAsignacionVehiculo`.
enum MotivoTerminoAsignacionLineaTelefonica {
  cambioResponsable(seleccionableManualmente: false),
  liberacion(seleccionableManualmente: true),

  /// Automático — lo coloca `LineaTelefonicaRepositoryImpl.darDeBaja`
  /// al cerrar la asignación vigente en la misma transacción que la
  /// baja de la línea.
  bajaLinea(seleccionableManualmente: false),

  /// Automático — lo coloca `AsignacionLineaTelefonicaRepositoryImpl
  /// .cerrarPorBajaEmpleado`, invocado desde
  /// `EmpleadoRepositoryImpl.registrarBajaLaboral` en la MISMA
  /// transacción que la baja laboral.
  ///
  /// Es un motivo propio y no una reutilización de `bajaLinea`, porque
  /// no son el mismo hecho: ahí se fue la LÍNEA, aquí se fue la
  /// PERSONA y la línea queda disponible para reasignarse. La
  /// Auditoría los distingue exactamente por este valor.
  bajaEmpleado(seleccionableManualmente: false),

  /// Automático — lo coloca el adaptador
  /// `LineaTelefonicaDeUnidadCoordinador` cuando **Inventario** termina
  /// la custodia del teléfono que traía la SIM (devolución, daño,
  /// pérdida, desecho), en la MISMA transacción de ese cierre.
  ///
  /// Motivo propio y no `liberacion`: nadie liberó la línea a mano, se
  /// fue el aparato. La Auditoría los distingue exactamente por este
  /// valor, igual que distingue `bajaLinea` de `bajaEmpleado`.
  custodiaEquipoTerminada(seleccionableManualmente: false),

  /// Automático — el aparato que traía la SIM se transfirió a otro
  /// responsable en Inventario, y la línea viajó con él. El periodo
  /// anterior se cierra con ESTE motivo y no con `cambioResponsable`,
  /// que significa "alguien cambió la línea a mano".
  sincronizacionCustodiaInventario(seleccionableManualmente: false),
  otro(seleccionableManualmente: true, requiereObservaciones: true);

  const MotivoTerminoAsignacionLineaTelefonica({required this.seleccionableManualmente, this.requiereObservaciones = false});

  final bool seleccionableManualmente;
  final bool requiereObservaciones;
}

/// Asignación administrativa de una línea telefónica a un Empleado o a
/// un Servicio (Etapa 9B) — "quién la usa" y "quién la ha usado antes".
/// Completamente independiente de `LineaTelefonicaEquipo` (qué teléfono
/// físico trae la SIM en este momento): un cambio de equipo no cierra
/// ni reabre esta tabla, y viceversa (ver el doc comment de
/// `LineaTelefonicaEquipo` para el razonamiento completo).
///
/// Mismo molde exacto que `AsignacionVehiculo` (Etapa 8B) — FK reales
/// de empleado/servicio, sin `ownerType`/`ownerId`, `fechaTermino IS
/// NULL` = vigente, sin columna `estatus` separada.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_asignacion_linea_telefonica_vigente '
  'ON asignacion_linea_telefonica (linea_telefonica_id) WHERE fecha_termino IS NULL',
)
class AsignacionLineaTelefonica extends Table with AuditColumns {
  TextColumn get lineaTelefonicaId => text().references(LineaTelefonica, #id, onDelete: KeyAction.restrict)();

  TextColumn get empleadoId => text().nullable().references(Empleado, #id, onDelete: KeyAction.restrict)();

  TextColumn get servicioId => text().nullable().references(Servicio, #id, onDelete: KeyAction.restrict)();

  DateTimeColumn get fechaInicio => dateTime()();

  DateTimeColumn get fechaTermino => dateTime().nullable()();

  TextColumn get motivoTermino => text().nullable()();

  TextColumn get observaciones => text().nullable()();

  TextColumn get observacionesTermino => text().nullable()();

  /// **Etapa 9D** — el UseCase/repositorio ya recibían `actorUsuarioId`
  /// desde la Etapa 9B, pero la columna nunca existió y el valor se
  /// descartaba silenciosamente. Se agrega ahora porque el punto 11 de
  /// la Etapa 9D exige que "asociación/cambio de línea" sea trazable.
  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  @override
  List<String> get customConstraints => [
        'CHECK ((empleado_id IS NOT NULL AND servicio_id IS NULL) OR '
            '(empleado_id IS NULL AND servicio_id IS NOT NULL))',
        'CHECK (fecha_termino IS NULL OR fecha_termino >= fecha_inicio)',
      ];
}
