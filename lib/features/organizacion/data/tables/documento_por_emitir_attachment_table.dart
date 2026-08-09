import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import 'documento_por_emitir_table.dart';

/// Tabla puente DocumentoPorEmitir↔Attachment (Etapa 5A) — reemplaza el
/// brazo `documentoPorEmitirId` que antes vivía directo en `Attachment`
/// (ver el doc comment de esa tabla).
class DocumentoPorEmitirAttachment extends Table {
  TextColumn get attachmentId => text().references(Attachment, #id, onDelete: KeyAction.cascade)();

  TextColumn get documentoPorEmitirId => text().references(DocumentoPorEmitir, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {attachmentId};
}
