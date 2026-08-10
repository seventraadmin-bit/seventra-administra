import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import 'asignacion_table.dart';

/// Tabla puente Asignacion↔Attachment (Etapa 7B) — misma forma exacta
/// que `MovimientoInventarioAttachment`. Creada sin uso todavía: deja
/// lista la infraestructura para que 7C adjunte el documento de
/// resguardo firmado a cada Asignación incluida, sin migración nueva.
class AsignacionAttachment extends Table {
  TextColumn get attachmentId => text().references(Attachment, #id, onDelete: KeyAction.cascade)();

  TextColumn get asignacionId => text().references(Asignacion, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {attachmentId};
}
