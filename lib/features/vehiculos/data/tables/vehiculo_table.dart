import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import '../../../../core/database/tables/audit_columns.dart';
import '../../../usuarios/data/tables/usuario_table.dart';

/// Catálogo simple, no administrable — mismo criterio que
/// `Articulo.unidadMedida` (texto validado en dominio en vez de tabla
/// propia): la variedad real de tipos de vehículo no justifica un
/// catálogo aparte.
enum TipoVehiculo { sedan, pickup, van, suv, motocicleta, otro }

/// Condición operativa real del vehículo (Etapa 8A) — deliberadamente
/// distinto de `AuditColumns.cicloVidaRegistro` (ese eje es "¿el
/// registro técnico sigue contando?"; este es "¿qué está pasando con
/// el vehículo hoy?"), mismo criterio que ya usa `EstatusArticuloUnidad`
/// (que también incluye su propio valor `baja` sin que eso choque con
/// `cicloVidaRegistro`).
///
/// `asignado` se mantiene transaccionalmente desde `AsignacionVehiculo`
/// (Etapa 8B) — nunca se escribe a mano para esa transición, mismo
/// criterio que `EstatusArticuloUnidad.asignado` en Inventario. Hasta
/// que 8B exista, ningún flujo produce este valor todavía.
enum EstatusVehiculo { disponible, asignado, enMantenimiento, fueraDeServicio, baja }

/// Motivo de baja (Etapa 8A) — enum enriquecido, mismo mecanismo que
/// `MotivoBajaEmpleado`/`MotivoTerminoAsignacion`: la propiedad vive en
/// cada valor, no en una lista aparte. `robo`/`perdidaTotal` exigen
/// observaciones igual que `otro` — así el contexto (reporte policial,
/// aseguradora, fecha del hecho) queda capturado obligatoriamente sin
/// necesitar una tabla de eventos adicional.
enum MotivoBajaVehiculo {
  venta(requiereObservaciones: false),
  perdidaTotal(requiereObservaciones: true),
  robo(requiereObservaciones: true),
  finVidaUtil(requiereObservaciones: false),
  otro(requiereObservaciones: true);

  const MotivoBajaVehiculo({required this.requiereObservaciones});

  final bool requiereObservaciones;
}

/// El expediente de la flotilla (Etapa 8A) — "qué vehículo es", nunca
/// "quién lo tiene" (`AsignacionVehiculo`, Etapa 8B), "cuánto
/// kilometraje tiene" (`VehiculoKilometraje`, Etapa 8B) ni "qué
/// documentos/mantenimiento tiene" (Etapas 8C/8D) — mismo criterio de
/// separación que `Articulo` en Inventario.
///
/// `placas`/`vin` son opcionales (un vehículo recién adquirido puede no
/// tener placas todavía) pero únicos cuando se capturan — ver los
/// índices únicos parciales abajo, mismo mecanismo que
/// `idx_asignacion_servicio_empleado_activa`.
///
/// `fechaBaja`/`motivoBaja`/`observacionesBaja` viven directamente en
/// esta fila (no una tabla de periodos como `EmpleadoPeriodoLaboral`):
/// a diferencia de un Empleado, nada en el alcance de Vehículos pide un
/// ciclo baja→reingreso — la baja es terminal.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_vehiculo_placas_unica '
  'ON vehiculo (placas) WHERE placas IS NOT NULL',
)
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_vehiculo_vin_unico '
  'ON vehiculo (vin) WHERE vin IS NOT NULL',
)
class Vehiculo extends Table with AuditColumns {
  TextColumn get codigo => text().unique()();

  TextColumn get marca => text()();

  TextColumn get modelo => text()();

  IntColumn get anio => integer().nullable()();

  TextColumn get color => text().nullable()();

  TextColumn get placas => text().nullable()();

  TextColumn get vin => text().nullable()();

  TextColumn get numeroMotor => text().nullable()();

  TextColumn get tipoVehiculo => text()();

  TextColumn get estatus => text().withDefault(const Constant('disponible'))();

  DateTimeColumn get fechaAdquisicion => dateTime().nullable()();

  IntColumn get costoAdquisicion => integer().nullable()();

  TextColumn get observaciones => text().nullable()();

  TextColumn get fotografiaAttachmentId =>
      text().nullable().references(Attachment, #id, onDelete: KeyAction.restrict)();

  DateTimeColumn get fechaBaja => dateTime().nullable()();

  TextColumn get motivoBaja => text().nullable()();

  TextColumn get observacionesBaja => text().nullable()();

  @override
  List<String> get customConstraints => [
        'CHECK (costo_adquisicion IS NULL OR costo_adquisicion >= 0)',
        "CHECK ((estatus = 'baja' AND fecha_baja IS NOT NULL) OR "
            "(estatus != 'baja' AND fecha_baja IS NULL))",
      ];
}

/// Tabla puente Vehiculo↔Attachment (Etapa 8A) — mismo patrón exacto
/// que `EmpresaAttachment`/`EmpleadoAttachment`: además del puntero
/// directo `Vehiculo.fotografiaAttachmentId` (acceso O(1) a "la
/// fotografía actual"), cada adjunto también se liga aquí para que
/// "todos los adjuntos generales de este vehículo" sea una consulta
/// uniforme. Los documentos con vencimiento (Etapa 8C) y los
/// comprobantes de mantenimiento (Etapa 8D) usan sus propias tablas
/// puente contra su fila puntual, no esta.
class VehiculoAttachment extends Table {
  TextColumn get attachmentId => text().references(Attachment, #id, onDelete: KeyAction.cascade)();

  TextColumn get vehiculoId => text().references(Vehiculo, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {attachmentId};
}

/// Tipos de evento del historial de un Vehículo (schemaVersion 80) —
/// mismo criterio append-only que `TiempoExtraEvento`/`CompraEvento`.
///
/// Cubre el expediente Y sus subentidades: un mantenimiento corregido o
/// anulado, un documento corregido, una lectura de kilometraje — todo
/// deja rastro en el historial del Vehículo, que es la unidad que el
/// usuario consulta. No se crea una tabla de eventos por subentidad
/// (sería historial fragmentado de un mismo activo).
enum TipoEventoVehiculo {
  creado,
  corregido,
  estatusCambiado,
  dadoDeBaja,
  mantenimientoRegistrado,
  mantenimientoCorregido,
  mantenimientoCancelado,
  documentoRegistrado,
  documentoCorregido,
  kilometrajeRegistrado,
  asignacionRegistrada,
  asignacionRetirada,
}

/// Historial append-only del Vehículo (schemaVersion 80) — cierra el
/// gap P0 de la auditoría de la v79: hasta esta etapa `CorregirVehiculo`
/// podía cambiar placas, VIN, número de motor y costo de adquisición
/// sin motivo, sin actor y sin dejar rastro. Era la única excepción del
/// proyecto.
///
/// Mismo shape exacto que `TiempoExtraEvento`, para que la auditoría
/// central lo agregue sin ningún caso especial.
class VehiculoEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get vehiculoId => text().references(Vehiculo, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get fechaHora => dateTime()();

  TextColumn get tipoEvento => text()();

  TextColumn get observacion => text().nullable()();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  TextColumn get estadoAnterior => text().nullable()();

  TextColumn get estadoNuevo => text().nullable()();

  /// Diferencias campo a campo de una corrección (`DiffEvento`) — mismo
  /// formato que el resto del proyecto: solo los campos REALMENTE
  /// modificados, nunca el registro completo.
  TextColumn get datosRelevantes => text().nullable()();
}
