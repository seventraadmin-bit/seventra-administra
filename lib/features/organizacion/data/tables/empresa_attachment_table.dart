import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import 'empresa_table.dart';

/// Tabla puente Empresa↔Attachment (Etapa 5A) — reemplaza el brazo
/// `empresaId` que antes vivía directo en `Attachment` (ver el doc
/// comment de esa tabla). `attachmentId` es la llave primaria: un
/// Attachment pertenece a lo más a una Empresa dentro de esta tabla.
class EmpresaAttachment extends Table {
  TextColumn get attachmentId => text().references(Attachment, #id, onDelete: KeyAction.cascade)();

  TextColumn get empresaId => text().references(Empresa, #id, onDelete: KeyAction.restrict)();

  @override
  Set<Column> get primaryKey => {attachmentId};
}
