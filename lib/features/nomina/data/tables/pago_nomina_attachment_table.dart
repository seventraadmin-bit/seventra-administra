import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import 'pago_nomina_table.dart';

/// Tabla puente PagoNomina↔Attachment (Etapa 6D) — comprobantes de un
/// lote de pago (ej. captura de transferencia bancaria), misma forma
/// exacta que `EgresoAttachment`/`PagoAttachment` (ver el doc comment
/// de `Attachment` sobre el rediseño de brazo-exclusivo a tabla puente
/// por dominio, Etapa 5A).
class PagoNominaAttachment extends Table {
  TextColumn get attachmentId => text().references(Attachment, #id, onDelete: KeyAction.cascade)();

  TextColumn get pagoNominaId => text().references(PagoNomina, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {attachmentId};
}
