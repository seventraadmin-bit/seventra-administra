import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import '../../../../core/database/tables/audit_columns.dart';
import 'vehiculo_table.dart';

/// Catálogo de tipos de documento vehicular (Etapa 8C) — mínimo pedido
/// por Marlon. `otro` exige una descripción propia (ver
/// `VehiculoDocumento.tipoOtroDescripcion`) — sin eso, "Otro" es un
/// dato inútil para diferenciar dos documentos distintos en el
/// histórico.
enum TipoDocumentoVehiculo {
  tarjetaCirculacion,
  seguro,
  verificacion,
  tenenciaRefrendo,
  facturaCartaFactura,
  poliza,
  otro,
}

/// Un documento administrativo de un Vehículo (Etapa 8C) — tarjeta de
/// circulación, seguro, verificación, etc. `fechaVencimiento` es
/// deliberadamente nullable: no todo documento vence (una factura no
/// tiene vigencia) — "vigente/próximo a vencer/vencido" se deriva en
/// dominio (`calcularEstadoVigencia`), nunca se guarda aquí.
///
/// **Renovación = fila nueva, nunca se edita una existente** — mismo
/// principio append-only que `AsignacionServicio`/`EmpleadoPeriodoLaboral`/
/// `ServicioLineaComercialVigencia`: cuando el seguro se renueva, se
/// inserta un `VehiculoDocumento` nuevo (mismo `tipo`, nuevas fechas/
/// folio/adjunto); el anterior queda como historial de ese tipo. "El
/// documento vigente de un tipo" = la fila más reciente por
/// `fechaEmision` (o `createdAt` si `fechaEmision` es nula) para ese
/// tipo — una consulta, nunca una bandera `esVigente`.
///
/// Deliberadamente **sin** columna `costo` en esta etapa (8C) —
/// instrucción explícita de Marlon: "no quiero todavía mantenimiento
/// ni gastos". Si una etapa futura de costos la necesita, es una
/// migración aditiva simple.
class VehiculoDocumento extends Table with AuditColumns {
  TextColumn get vehiculoId => text().references(Vehiculo, #id, onDelete: KeyAction.restrict)();

  TextColumn get tipo => text()();

  /// Solo aplica cuando `tipo == otro` — el nombre/descripción real del
  /// documento (ej. "Constancia de no adeudo"). Obligatorio en ese caso
  /// (validado en `RegistrarDocumentoVehiculoUseCase`, no por `CHECK`:
  /// mismo criterio que el resto del proyecto para reglas que dependen
  /// del valor de otra columna tipo-enum).
  TextColumn get tipoOtroDescripcion => text().nullable()();

  TextColumn get numeroFolio => text().nullable()();

  DateTimeColumn get fechaEmision => dateTime().nullable()();

  DateTimeColumn get fechaVencimiento => dateTime().nullable()();

  TextColumn get observaciones => text().nullable()();

  @override
  List<String> get customConstraints => [
        'CHECK (fecha_vencimiento IS NULL OR fecha_emision IS NULL OR fecha_vencimiento >= fecha_emision)',
      ];
}

/// Tabla puente VehiculoDocumento↔Attachment (Etapa 8C) — mismo patrón
/// exacto que `MovimientoInventarioAttachment`: el adjunto pertenece al
/// registro puntual (el documento concreto), no al Vehículo directo
/// (esa vía ya existe para la fotografía principal vía
/// `VehiculoAttachment`/`Vehiculo.fotografiaAttachmentId`, deliberadamente
/// separada — Marlon: "no mezclar fotografía del vehículo con
/// documentos"). Permite varios adjuntos por documento (ej. anverso y
/// reverso de una tarjeta de circulación) sin forzar 1:1.
class VehiculoDocumentoAttachment extends Table {
  TextColumn get attachmentId => text().references(Attachment, #id, onDelete: KeyAction.cascade)();

  TextColumn get vehiculoDocumentoId => text().references(VehiculoDocumento, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {attachmentId};
}
