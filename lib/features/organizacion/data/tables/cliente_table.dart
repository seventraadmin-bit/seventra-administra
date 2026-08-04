import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../../core/database/tables/catalogos_tables.dart';

/// Ciclo comercial real de un Cliente — independiente de
/// `cicloVidaRegistro`. "activo" aquí significa "cliente vigente
/// comercialmente", no "registro no archivado"; ambos conceptos pueden
/// discrepar (un cliente `terminado` hace años sigue teniendo su fila
/// intacta, solo cambia de `cicloVidaRegistro` si algún día se archiva).
enum EstatusCliente { prospecto, activo, suspendido, terminado, descartado }

class Cliente extends Table with AuditColumns {
  TextColumn get codigo => text().unique()();

  TextColumn get razonSocial => text()();

  TextColumn get nombreComercial => text().nullable()();

  /// Nullable — un Prospecto puede no tener RFC todavía. Normalización
  /// (mayúsculas, sin espacios) y validación de forma ocurren en
  /// `CrearClienteUseCase`, no aquí.
  TextColumn get rfc => text().nullable().unique()();

  TextColumn get industriaId => text().nullable().references(Industria, #id)();

  // Literal en vez de referencia al enum: ver la nota en
  // `AuditColumns.cicloVidaRegistro` sobre por qué (mismo SQL resultante).
  TextColumn get estatus => text().withDefault(const Constant('prospecto'))();

  DateTimeColumn get fechaAlta => dateTime().withDefault(currentDateAndTime)();

  TextColumn get observaciones => text().nullable()();
}
