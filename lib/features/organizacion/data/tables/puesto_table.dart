import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../../core/database/tables/catalogos_tables.dart';

/// Función laboral (Guardia, Supervisor, RH, ...) — nunca debe
/// confundirse con un rol de acceso al sistema. `Puesto` no otorga
/// permisos automáticamente; cuando exista el motor de roles, será solo
/// una sugerencia por defecto al dar de alta a un empleado, nunca una
/// concesión directa. Esa FK (`rolSugeridoId`) no se agrega todavía —
/// `Rol` no existe en esta etapa.
enum TipoPuesto { operativo, administrativo }

/// Sin campo `estado` propio — no tiene un estado de negocio distinto de
/// "existe / no existe", que ya cubre `cicloVidaRegistro`.
class Puesto extends Table with AuditColumns {
  TextColumn get codigo => text().unique()();

  TextColumn get nombre => text()();

  TextColumn get areaId => text().references(Area, #id)();

  TextColumn get tipo => text()();

  TextColumn get descripcion => text().nullable()();

  IntColumn get nivelJerarquico => integer()();
}
