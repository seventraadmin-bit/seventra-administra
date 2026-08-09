import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import 'ingreso_table.dart';

/// Tabla puente Ingreso↔Attachment (Etapa 5A) — reemplaza el brazo
/// `ingresoId` que antes vivía directo en `Attachment` (ver el doc
/// comment de esa tabla).
class IngresoAttachment extends Table {
  TextColumn get attachmentId => text().references(Attachment, #id, onDelete: KeyAction.cascade)();

  TextColumn get ingresoId => text().references(Ingreso, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {attachmentId};
}
