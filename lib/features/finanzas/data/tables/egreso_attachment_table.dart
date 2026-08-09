import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import 'egreso_table.dart';

/// Tabla puente Egreso↔Attachment (Etapa 5A) — reemplaza el brazo
/// `egresoId` que antes vivía directo en `Attachment` (ver el doc
/// comment de esa tabla).
class EgresoAttachment extends Table {
  TextColumn get attachmentId => text().references(Attachment, #id, onDelete: KeyAction.cascade)();

  TextColumn get egresoId => text().references(Egreso, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {attachmentId};
}
