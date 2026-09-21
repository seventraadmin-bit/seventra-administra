import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import '../../../../core/database/tables/audit_columns.dart';
import '../../../finanzas/data/tables/deuda_table.dart';
import '../../../finanzas/data/tables/egreso_table.dart';
import '../../../usuarios/data/tables/usuario_table.dart';
import 'vehiculo_table.dart';

/// Catálogo unificado de mantenimiento e incidencias (Etapa 8D) —
/// **una sola tabla, un solo catálogo**, decisión explícita pedida por
/// Marlon ("analiza si conviene una entidad separada"): operacionalmente
/// un golpe/avería/accidente y un cambio de frenos son el mismo hecho
/// (algo le pasó al vehículo, en una fecha, a un kilometraje, con un
/// costo posible, con evidencia opcional) — la única diferencia es la
/// naturaleza del evento, que ya cabe como un valor más de `tipo`.
/// Separar en dos tablas obligaría a decidir en cuál va cada
/// "golpe-que-generó-una-reparación", justo la duplicación que Marlon
/// pidió evitar. `esIncidencia` (propiedad por valor, mismo mecanismo
/// que `MotivoBajaVehiculo.requiereObservaciones`) es lo único que
/// distingue las dos mitades del catálogo — usado para filtrar la UI y
/// para separar los dos totales de costo (punto 6).
enum TipoMantenimientoVehiculo {
  preventivo(esIncidencia: false),
  correctivo(esIncidencia: false),
  servicioGeneral(esIncidencia: false),
  llantas(esIncidencia: false),
  frenos(esIncidencia: false),
  bateria(esIncidencia: false),
  otro(esIncidencia: false),
  averia(esIncidencia: true),
  golpe(esIncidencia: true),
  accidente(esIncidencia: true),
  dano(esIncidencia: true),
  reparacion(esIncidencia: true);

  const TipoMantenimientoVehiculo({required this.esIncidencia});

  final bool esIncidencia;
}

/// Un evento de mantenimiento o incidencia de un Vehículo (Etapa 8D) —
/// ver el doc comment de `TipoMantenimientoVehiculo` para por qué ambos
/// conceptos comparten esta tabla. `descripcion` es obligatoria para
/// **todo** registro (no solo `tipo == otro`): a diferencia de
/// `VehiculoDocumento.tipoOtroDescripcion`, aquí no hace falta un campo
/// condicional aparte — "Otro requiere descripción clara" ya queda
/// cubierto por la obligatoriedad general del campo.
///
/// `kilometraje` es opcional y, cuando se captura, alimenta
/// `VehiculoKilometraje` como una fila más (origen `mantenimiento`, ya
/// reservado desde la Etapa 8B) en la misma transacción que este
/// registro — nunca una fuente paralela (ver
/// `VehiculoMantenimientoRepositoryImpl.crear`).
///
/// `proximoMantenimientoFecha`/`proximoMantenimientoKilometraje` son
/// ambos opcionales e independientes — el "próximo mantenimiento" de un
/// Vehículo se deriva siempre de la fila más reciente que tenga alguno
/// de los dos capturado (`calcularProximoMantenimiento`), nunca se
/// guarda en `Vehiculo`.
@TableIndex.sql(
  'CREATE UNIQUE INDEX vehiculo_mantenimiento_egreso_unico '
  'ON vehiculo_mantenimiento (egreso_id) WHERE egreso_id IS NOT NULL',
)
class VehiculoMantenimiento extends Table with AuditColumns {
  TextColumn get vehiculoId => text().references(Vehiculo, #id, onDelete: KeyAction.restrict)();

  DateTimeColumn get fecha => dateTime()();

  IntColumn get kilometraje => integer().nullable()();

  TextColumn get tipo => text()();

  TextColumn get descripcion => text()();

  TextColumn get tallerProveedor => text().nullable()();

  IntColumn get costo => integer().nullable()();

  DateTimeColumn get proximoMantenimientoFecha => dateTime().nullable()();

  IntColumn get proximoMantenimientoKilometraje => integer().nullable()();

  TextColumn get observaciones => text().nullable()();

  /// Quién registró el mantenimiento/incidencia (Etapa 11D) — mismo
  /// criterio que `actorUsuarioId` en el resto del proyecto.
  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  /// Origen financiero del gasto (schemaVersion 80) — mismo patrón dual
  /// exacto que `Compra.egresoId`/`Compra.deudaId` y
  /// `TiempoExtra.egresoId`/`TiempoExtra.deudaId`, nunca un concepto
  /// nuevo: `OrigenFinancieroGasto` es la abstracción compartida.
  ///
  /// `egresoId` se puebla cuando el gasto sale de una CuentaFinanciera;
  /// `deudaId` cuando se carga a una tarjeta de crédito. Son mutuamente
  /// excluyentes — un gasto con TDC **nunca** genera además un Egreso
  /// (la salida de banco ocurre después, al pagar la tarjeta).
  ///
  /// Ambos nulos con `costo > 0` significa **gasto histórico sin origen
  /// especificado**: las filas anteriores a esta etapa se conservan tal
  /// cual, sin backfill heurístico (decisión de Marlon, mismo criterio
  /// que la etapa de Egresos v76). Los mantenimientos NUEVOS con costo
  /// sí exigen origen — lo impone `RegistrarMantenimientoVehiculoUseCase`,
  /// no un CHECK, porque el legacy debe seguir siendo válido.
  /// Único cuando existe — un Egreso pertenece a un solo mantenimiento,
  /// igual que en `Compra`/`TiempoExtra`. Se declara como índice único
  /// PARCIAL (ver la anotación de la clase) y NO como `.unique()` de
  /// columna, porque SQLite no admite
  /// `ALTER TABLE … ADD COLUMN … UNIQUE` y esta columna se agrega en la
  /// v80 sobre una tabla que ya existe (encontrado al correr las
  /// pruebas de migración).
  TextColumn get egresoId => text().nullable().references(Egreso, #id, onDelete: KeyAction.restrict)();

  TextColumn get deudaId => text().nullable().references(Deuda, #id, onDelete: KeyAction.restrict)();

  /// Anulación sin borrar (schemaVersion 80) — un error de captura
  /// nunca obliga a destruir historial. Revierte exactamente el efecto
  /// financiero (cancela el Egreso, o revierte el cargo de la TDC) y
  /// deja la fila con su evidencia.
  TextColumn get estatus => text().withDefault(const Constant('registrado'))();

  TextColumn get motivoCancelacion => text().nullable()();

  @override
  List<String> get customConstraints => [
        'CHECK (kilometraje IS NULL OR kilometraje >= 0)',
        'CHECK (costo IS NULL OR costo >= 0)',
        'CHECK (proximo_mantenimiento_kilometraje IS NULL OR proximo_mantenimiento_kilometraje >= 0)',
        'CHECK (proximo_mantenimiento_fecha IS NULL OR proximo_mantenimiento_fecha >= fecha)',
        // `egresoId`/`deudaId` son mutuamente excluyentes, pero eso NO
        // se expresa como CHECK de tabla: SQLite no permite añadir uno
        // por `ALTER TABLE`, y estas columnas se agregan en la v80 sobre
        // una tabla existente (encontrado por las pruebas de migración —
        // la tabla migrada quedaba con 5 constraints y la nueva con 6).
        //
        // Es un invariante de DOMINIO, exactamente igual que en
        // `TiempoExtra.egresoId`/`deudaId`, que tampoco lo declara aquí:
        // `RegistrarMantenimientoVehiculoUseCase` sólo puede producir
        // uno de los dos, y el repositorio es el único escritor.
      ];
}

/// Estatus de un registro de mantenimiento/incidencia (schemaVersion
/// 80) — mismo par exacto que `TiempoExtra`/`Compra`.
enum EstatusMantenimientoVehiculo { registrado, cancelado }

/// Tabla puente VehiculoMantenimiento↔Attachment (Etapa 8D) — mismo
/// patrón exacto que `VehiculoDocumentoAttachment`: el comprobante (o la
/// evidencia fotográfica de una incidencia) pertenece al registro
/// puntual, no al Vehículo directo. Permite varios adjuntos por registro
/// (ej. foto del daño + factura del taller) sin forzar 1:1.
class VehiculoMantenimientoAttachment extends Table {
  TextColumn get attachmentId => text().references(Attachment, #id, onDelete: KeyAction.cascade)();

  TextColumn get vehiculoMantenimientoId => text().references(VehiculoMantenimiento, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {attachmentId};
}
