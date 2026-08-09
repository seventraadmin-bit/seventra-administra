import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import 'pago_table.dart';

/// Tabla puente Pago↔Attachment (Etapa 5A) — reemplaza el brazo
/// `pagoId` que antes vivía directo en `Attachment` (ver el doc comment
/// de esa tabla).
class PagoAttachment extends Table {
  TextColumn get attachmentId => text().references(Attachment, #id, onDelete: KeyAction.cascade)();

  TextColumn get pagoId => text().references(Pago, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {attachmentId};
}
