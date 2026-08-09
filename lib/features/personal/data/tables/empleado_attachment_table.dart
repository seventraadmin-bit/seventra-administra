import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import 'empleado_table.dart';

/// Tabla puente Empleado↔Attachment (Etapa 5A) — documentación del
/// expediente (INE, CURP, RFC, acta de nacimiento, comprobante de
/// domicilio, NSS, cartilla, licencias, certificados, constancias,
/// contratos, y cualquier documento futuro vía `otro`). Personal nace
/// directamente con este patrón de tabla puente — nunca tuvo un brazo
/// dedicado en la forma antigua de `Attachment`.
class EmpleadoAttachment extends Table {
  TextColumn get attachmentId => text().references(Attachment, #id, onDelete: KeyAction.cascade)();

  TextColumn get empleadoId => text().references(Empleado, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {attachmentId};
}
