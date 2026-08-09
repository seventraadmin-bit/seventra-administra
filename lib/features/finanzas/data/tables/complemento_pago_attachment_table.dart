import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import 'complemento_pago_table.dart';

/// Tabla puente ComplementoPago↔Attachment (Etapa 5A) — reemplaza el
/// brazo `complementoPagoId` que antes vivía directo en `Attachment`
/// (ver el doc comment de esa tabla).
class ComplementoPagoAttachment extends Table {
  TextColumn get attachmentId => text().references(Attachment, #id, onDelete: KeyAction.cascade)();

  TextColumn get complementoPagoId => text().references(ComplementoPago, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {attachmentId};
}
