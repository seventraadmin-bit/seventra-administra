import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import 'compra_table.dart';

/// Tabla puente Compra↔Attachment (Etapa 10) — el comprobante/factura
/// PDF, opcional y único, mismo molde exacto que `EgresoAttachment`/
/// `RecargaLineaTelefonicaAttachment`.
class CompraAttachment extends Table {
  TextColumn get attachmentId => text().references(Attachment, #id, onDelete: KeyAction.cascade)();

  TextColumn get compraId => text().references(Compra, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {attachmentId};
}
