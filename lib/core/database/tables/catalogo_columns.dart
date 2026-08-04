import 'package:drift/drift.dart';

/// Columnas compartidas por los catálogos abiertos y editables
/// (TipoSucursal, Industria, TipoServicio, Area, ...).
///
/// Deliberadamente distinto de [AuditColumns]: un catálogo es dato de
/// referencia, no un registro de negocio auditado — usa un `activo`
/// booleano simple en vez del eje completo de `cicloVidaRegistro`, y su
/// `id` no se autogenera porque las filas de catálogo se siembran con
/// IDs estables y conocidos (ver `seed_ids.dart`), nunca se crean desde
/// una pantalla en esta etapa.
mixin CatalogoColumns on Table {
  TextColumn get id => text()();

  TextColumn get codigo => text()();

  TextColumn get nombre => text()();

  TextColumn get descripcion => text().nullable()();

  BoolColumn get activo => boolean().withDefault(const Constant(true))();

  IntColumn get orden => integer().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
