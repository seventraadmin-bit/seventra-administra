import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Eje transversal de ciclo de vida técnico de un registro — nunca debe
/// confundirse con el `estado`/`estatus` propio de cada entidad (ver
/// [AuditColumns]).
enum CicloVidaRegistro { activo, inactivo, archivado, baja, borradoLogico }

/// Columnas de auditoría mínimas compartidas por toda entidad de negocio.
///
/// `createdBy`/`updatedBy` se difieren deliberadamente — no existe todavía
/// un motor de usuarios/autenticación, y sembrar un usuario ficticio solo
/// para llenar esas columnas no aporta nada verificable hoy. Se agregan
/// por migración aditiva cuando exista Usuario real.
///
/// Regla para decidir si una entidad necesita un campo de negocio propio
/// además de [cicloVidaRegistro]: si el único valor que necesitas es
/// "existe / no existe", no crees un campo nuevo — usa este. Un campo de
/// negocio propio (`estatus`, `estadoOperativo`, ...) solo se justifica
/// cuando expresa algo que este eje no cubre (ej. el ciclo comercial de
/// un Cliente, que es independiente de si el registro sigue vigente en
/// la base de datos).
mixin AuditColumns on Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  // Literal 'activo' en vez de `Constant(CicloVidaRegistro.activo.name)`:
  // el snapshot de esquema (drift_schemas/) para las pruebas de
  // migración serializa el valor por defecto como texto Dart literal, y
  // ese texto se reusa en un archivo generado sin el import del enum —
  // un literal evita esa dependencia sin cambiar el SQL resultante (es
  // exactamente el mismo string).
  TextColumn get cicloVidaRegistro => text().withDefault(const Constant('activo'))();

  @override
  Set<Column> get primaryKey => {id};
}
