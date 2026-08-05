import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import 'cliente_table.dart';

/// Clasificación de un [Contacto] — comercial (trato de venta/cobranza)
/// u operativo (trato del día a día del servicio). Un mismo Cliente
/// puede tener varios contactos de cada tipo; lo que se restringe es
/// cuántos pueden estar marcados como principal a la vez (ver el índice
/// de la tabla).
enum TipoContacto { comercial, operativo }

/// Persona de contacto de un Cliente.
///
/// El único dueño real en el alcance actual (4A–4F) es `Cliente` — a
/// diferencia de `Direccion`/`MedioContacto`/`Attachment`, aquí no hace
/// falta el patrón de arco exclusivo: con un solo dueño posible, una FK
/// simple y requerida es toda la flexibilidad que existe que usar hoy.
/// `Servicio.responsableClienteContactoId` referencia esta misma tabla.
///
/// Puede haber como máximo un contacto principal **activo** por Cliente
/// y tipo (un principal comercial + un principal operativo) — nunca dos
/// del mismo tipo simultáneamente. El índice solo considera filas con
/// `ciclo_vida_registro = 'activo'`: un contacto archivado no bloquea
/// que otro tome su lugar como principal de ese tipo.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_contacto_cliente_tipo_principal_activo '
  'ON contacto (cliente_id, tipo) '
  "WHERE es_principal = 1 AND ciclo_vida_registro = 'activo'",
)
class Contacto extends Table with AuditColumns {
  TextColumn get clienteId =>
      text().references(Cliente, #id, onDelete: KeyAction.restrict)();

  TextColumn get nombre => text()();

  TextColumn get puesto => text().nullable()();

  TextColumn get telefono => text().nullable()();

  TextColumn get correo => text().nullable()();

  BoolColumn get esPrincipal => boolean().withDefault(const Constant(false))();

  // Literal en vez de referencia al enum: ver la nota en
  // `AuditColumns.cicloVidaRegistro` sobre por qué (mismo SQL resultante).
  // Sin default: toda inserción pasa por `AgregarContactoUseCase`, que
  // siempre especifica el tipo explícitamente.
  TextColumn get tipo => text()();
}
