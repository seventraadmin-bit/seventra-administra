import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import '../../../../core/database/tables/audit_columns.dart';
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

  @override
  List<String> get customConstraints => [
        'CHECK (kilometraje IS NULL OR kilometraje >= 0)',
        'CHECK (costo IS NULL OR costo >= 0)',
        'CHECK (proximo_mantenimiento_kilometraje IS NULL OR proximo_mantenimiento_kilometraje >= 0)',
        'CHECK (proximo_mantenimiento_fecha IS NULL OR proximo_mantenimiento_fecha >= fecha)',
      ];
}

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
