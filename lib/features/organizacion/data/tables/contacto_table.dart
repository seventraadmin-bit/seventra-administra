import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import 'cliente_table.dart';

/// Persona de contacto de un Cliente.
///
/// El único dueño real en el alcance actual (4A–4F) es `Cliente` — a
/// diferencia de `Direccion`/`MedioContacto`/`Attachment`, aquí no hace
/// falta el patrón de arco exclusivo: con un solo dueño posible, una FK
/// simple y requerida es toda la flexibilidad que existe que usar hoy.
/// `Servicio.responsableClienteContactoId` referencia esta misma tabla.
class Contacto extends Table with AuditColumns {
  TextColumn get clienteId =>
      text().references(Cliente, #id, onDelete: KeyAction.restrict)();

  TextColumn get nombre => text()();

  TextColumn get puesto => text().nullable()();

  TextColumn get telefono => text().nullable()();

  TextColumn get correo => text().nullable()();

  BoolColumn get esPrincipal => boolean().withDefault(const Constant(false))();
}
