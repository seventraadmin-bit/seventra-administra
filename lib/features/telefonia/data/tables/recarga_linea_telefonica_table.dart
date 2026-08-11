import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import '../../../../core/database/tables/audit_columns.dart';
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
/// Deliberadamente **sin** `Egreso` automático — Telefonía registra
/// únicamente el contexto operativo ("se recargaron $200 a esta
/// línea"); Finanzas sigue siendo la única fuente de movimientos de
/// dinero reales (mismo criterio que Nómina/Finanzas antes de que
/// existiera la composición explícita en `PagoNominaRepositoryImpl`).
class RecargaLineaTelefonica extends Table with AuditColumns {
  TextColumn get lineaTelefonicaId => text().references(LineaTelefonica, #id, onDelete: KeyAction.restrict)();

  DateTimeColumn get fecha => dateTime()();

  IntColumn get importe => integer()();

  TextColumn get observaciones => text().nullable()();

  /// Quién registró la recarga (Etapa 11D) — mismo criterio que
  /// `actorUsuarioId` en el resto del proyecto.
  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  @override
  List<String> get customConstraints => [
        'CHECK (importe > 0)',
      ];
}

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
