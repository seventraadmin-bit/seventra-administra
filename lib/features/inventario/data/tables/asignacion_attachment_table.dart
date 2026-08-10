import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import 'asignacion_table.dart';

/// Tabla puente Asignacion↔Attachment. Creada sin uso en 7B; 7C la usa
/// para el documento de resguardo firmado.
///
/// Llave primaria **compuesta** (`attachmentId`, `asignacionId`) — a
/// diferencia de cualquier otra tabla puente de Attachment del
/// proyecto (todas 1:1, `primaryKey = {attachmentId}`), un resguardo
/// real normalmente cubre varios artículos entregados el mismo día:
/// una sola firma, varias Asignaciones. Con llave simple, el mismo
/// `attachmentId` no podría repetirse — forzaría un documento y una
/// firma por artículo, justo la fricción operativa que Inventario
/// evita en todo lo demás. Recreada en la Etapa 7C (`schemaVersion`
/// 28→29) porque nunca tuvo filas — sin backfill que preservar.
class AsignacionAttachment extends Table {
  TextColumn get attachmentId => text().references(Attachment, #id, onDelete: KeyAction.cascade)();

  TextColumn get asignacionId => text().references(Asignacion, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {attachmentId, asignacionId};
}
