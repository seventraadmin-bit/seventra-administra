import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import 'cliente_table.dart';

/// Entidad fiscal — razón social + RFC bajo los que se puede facturar a
/// un Cliente comercial. Un Cliente puede tener cero, una o varias
/// (ej. Sportium factura distinto por club); una Entidad fiscal
/// pertenece siempre a un único Cliente, y esa relación es inmutable
/// después de creada (`ActualizarEntidadFiscalUseCase` nunca acepta un
/// nuevo `clienteId` — no puede "trasladarse" a otro Cliente).
///
/// Sin campo de estatus propio: solo `cicloVidaRegistro` (activo/
/// archivado). No hay un valor de negocio distinto de "archivada" que
/// esta etapa necesite representar — mismo criterio que Área en la
/// Etapa 4D. Acciones visibles: Archivar/Reactivar, nunca Activar/
/// Desactivar (para no confundirse con un futuro estatus fiscal como
/// "pendiente de validación"/"bloqueada para facturación").
class EntidadFiscal extends Table with AuditColumns {
  TextColumn get codigo => text().unique()();

  TextColumn get clienteId =>
      text().references(Cliente, #id, onDelete: KeyAction.restrict)();

  TextColumn get razonSocial => text()();

  /// Único global (no solo por Cliente) — un RFC identifica una sola
  /// entidad legal. Verificado también en el caso de uso
  /// (`EntidadFiscalValidator`) para dar un error comprensible; esta
  /// restricción real protege concurrencia e importaciones futuras que
  /// no pasen por ese caso de uso.
  TextColumn get rfc => text().unique()();
}
