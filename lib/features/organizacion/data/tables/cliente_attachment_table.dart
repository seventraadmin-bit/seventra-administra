import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import 'cliente_table.dart';

/// Tabla puente Cliente↔Attachment (Etapa 5A) — reemplaza el brazo
/// `clienteId` que antes vivía directo en `Attachment` (ver el doc
/// comment de esa tabla).
class ClienteAttachment extends Table {
  TextColumn get attachmentId => text().references(Attachment, #id, onDelete: KeyAction.cascade)();

  TextColumn get clienteId => text().references(Cliente, #id, onDelete: KeyAction.restrict)();

  @override
  Set<Column> get primaryKey => {attachmentId};
}
