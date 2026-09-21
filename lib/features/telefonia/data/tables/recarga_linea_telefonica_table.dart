import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import '../../../../core/database/tables/audit_columns.dart';
import '../../../finanzas/data/tables/deuda_table.dart';
import '../../../finanzas/data/tables/egreso_table.dart';
import '../../../usuarios/data/tables/usuario_table.dart';
import 'linea_telefonica_table.dart';

/// Recarga registrada a una línea telefónica (Etapa 9C) — la operación
/// real de Telefonía en RISEG es prepago, sin planes ni contratos (ver
/// el doc comment de `LineaTelefonica`, `LineaTelefonicaPlan` fue
/// retirada en esta misma etapa). Deliberadamente mínima: fecha,
/// importe, observaciones opcionales — sin gigabytes, minutos, SMS,
/// paquete comercial, vigencia de paquete ni saldo restante
/// (confirmado fuera de alcance por Marlon).
///
/// **Sin snapshot de empleado/servicio** — a quién correspondía la
/// línea en el momento de una recarga se deriva consultando
/// `AsignacionLineaTelefonica` por rango de fecha (ver
/// `RecargaLineaTelefonicaRepositoryImpl.obtenerDestinoHistorico`), no
/// se duplica aquí. `AsignacionLineaTelefonica` ya es un historial
/// bien formado (nunca se edita, siempre cierra-y-abre) — exactamente
/// el tipo de dato que soporta esa derivación sin necesidad de
/// guardar un valor redundante.
///
/// **Etapa "Cierre integral de Telefonía" (schemaVersion 86)**: una
/// recarga ES una salida de dinero, y hasta v85 Finanzas no se
/// enteraba. La decisión original de la Etapa 9C —"deliberadamente sin
/// Egreso automático"— dejaba el gasto operativo incompleto: se
/// recargaban $200 reales y el resultado operativo seguía igual.
///
/// Ahora toda recarga NUEVA nace con exactamente un origen financiero,
/// con el MISMO patrón dual ya probado en `Compra`, `TiempoExtra` y
/// `VehiculoMantenimiento` — nunca una cuarta arquitectura:
///
/// - Cuenta financiera → `egresoId` (Egreso automático real).
/// - Tarjeta de crédito → `deudaId` (`MovimientoDeuda` de cargo,
///   NUNCA Egreso: la salida de banco ocurre al pagar la tarjeta).
///
/// Mutuamente excluyentes. Las recargas anteriores a v86 conservan
/// ambos en `NULL`: eso —y sólo eso— las identifica como "origen
/// financiero no registrado". No se les inventa cuenta, tarjeta ni
/// Egreso retroactivo.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_recarga_linea_telefonica_egreso_unico '
  'ON recarga_linea_telefonica (egreso_id) WHERE egreso_id IS NOT NULL',
)
class RecargaLineaTelefonica extends Table with AuditColumns {
  TextColumn get lineaTelefonicaId => text().references(LineaTelefonica, #id, onDelete: KeyAction.restrict)();

  DateTimeColumn get fecha => dateTime()();

  IntColumn get importe => integer()();

  TextColumn get observaciones => text().nullable()();

  /// Cómo se pagó — mismo catálogo `FormaPago` que ya usan Compras,
  /// Tiempos Extra y Egresos; nunca uno nuevo. `tarjeta` es lo que
  /// discrimina el origen TDC, exactamente igual que en esos módulos.
  /// `null` sólo en las recargas anteriores a v86.
  TextColumn get formaPago => text().nullable()();

  /// Poblado cuando la recarga se pagó desde una `CuentaFinanciera`.
  /// Mutuamente excluyente con [deudaId]. Único por índice parcial (ver
  /// el `@TableIndex.sql` de la clase): un Egreso jamás pertenece a dos
  /// recargas.
  TextColumn get egresoId => text().nullable().references(Egreso, #id, onDelete: KeyAction.restrict)();

  /// Poblado cuando la recarga se cargó directo a una tarjeta de
  /// crédito. Nunca genera Egreso — ver
  /// `DeudaRepository.registrarCargoRecargaLineaTelefonica`.
  TextColumn get deudaId => text().nullable().references(Deuda, #id, onDelete: KeyAction.restrict)();

  /// Quién registró la recarga (Etapa 11D) — mismo criterio que
  /// `actorUsuarioId` en el resto del proyecto.
  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  /// Anulacion sin borrar (schemaVersion 81) — un error de captura
  /// nunca obliga a destruir historial. La fila se conserva, deja de
  /// sumar en TODOS los totalizadores del modulo, y su anulacion queda
  /// como evento en `LineaTelefonicaEvento`.
  ///
  /// Mismo par exacto que `VehiculoMantenimiento`/`TiempoExtra`
  /// (`registrado`/`cancelado`) — nunca un tercer vocabulario.
  TextColumn get estatus => text().withDefault(const Constant('registrada'))();

  TextColumn get motivoCancelacion => text().nullable()();

  @override
  List<String> get customConstraints => [
        'CHECK (importe > 0)',
      ];
}

/// Estatus de una recarga (schemaVersion 81).
enum EstatusRecargaLineaTelefonica { registrada, cancelada }

/// Tabla puente RecargaLineaTelefonica↔Attachment (Etapa 9C) — el
/// comprobante de una recarga es opcional (Marlon: "únicamente si
/// realmente aporta valor; no debe ser obligatorio"), mismo patrón
/// exacto que `VehiculoDocumentoAttachment`: el adjunto pertenece a la
/// recarga puntual, no a la línea directa.
class RecargaLineaTelefonicaAttachment extends Table {
  TextColumn get attachmentId => text().references(Attachment, #id, onDelete: KeyAction.cascade)();

  TextColumn get recargaLineaTelefonicaId => text().references(RecargaLineaTelefonica, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {attachmentId};
}
