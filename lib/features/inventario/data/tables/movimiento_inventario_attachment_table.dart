import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import 'movimiento_inventario_table.dart';

/// Tabla puente MovimientoInventario↔Attachment (Etapa 7A) —
/// comprobante opcional de una entrada, misma forma exacta que
/// `EgresoAttachment`/`PagoAttachment`.
class MovimientoInventarioAttachment extends Table {
  TextColumn get attachmentId => text().references(Attachment, #id, onDelete: KeyAction.cascade)();

  TextColumn get movimientoInventarioId =>
      text().references(MovimientoInventario, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {attachmentId};
}
