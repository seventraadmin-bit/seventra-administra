import 'package:drift/drift.dart';

/// Configuración y contador de generación de códigos visibles.
///
/// `entityType` es la llave primaria (natural, no uuid) — es un
/// identificador de configuración, no una entidad de negocio con ciclo de
/// vida propio. Todo módulo que necesite un código visible pasa por
/// [GenerarCodigoUseCase]; ninguno debe leer o incrementar esta tabla
/// directamente.
class CodigoSecuencia extends Table {
  TextColumn get entityType => text()();

  TextColumn get prefijo => text()();

  IntColumn get digitos => integer()();

  BoolColumn get reseteaAnualmente => boolean().withDefault(const Constant(false))();

  IntColumn get anioActual => integer().nullable()();

  IntColumn get contadorActual => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {entityType};
}
