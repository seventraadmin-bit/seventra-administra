import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

import '../../domain/repositories/area_repository.dart';

class AreaRepositoryImpl implements AreaRepository {
  AreaRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<AreaData> crear({required String codigo, required String nombre, String? descripcion}) {
    return _db.into(_db.area).insertReturning(
          AreaCompanion.insert(
            id: const Uuid().v4(),
            codigo: codigo,
            nombre: nombre,
            descripcion: Value(descripcion),
          ),
        );
  }

  @override
  Future<AreaData> actualizar({required String id, required String nombre, String? descripcion}) async {
    await (_db.update(_db.area)..where((t) => t.id.equals(id))).write(
      AreaCompanion(
        nombre: Value(nombre),
        descripcion: Value(descripcion),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (_db.select(_db.area)..where((t) => t.id.equals(id))).getSingle();
  }

  @override
  Future<AreaData?> obtenerPorId(String id) {
    return (_db.select(_db.area)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<AreaData>> listarTodas() {
    return (_db.select(_db.area)..orderBy([(t) => OrderingTerm.asc(t.codigo)])).get();
  }

  @override
  Future<List<AreaData>> listarActivas() {
    return (_db.select(_db.area)
          ..where((t) => t.activo.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.codigo)]))
        .get();
  }

  @override
  Future<AreaData> activar(String id) => _cambiarActivo(id, true);

  @override
  Future<AreaData> desactivar(String id) => _cambiarActivo(id, false);

  Future<AreaData> _cambiarActivo(String id, bool activo) async {
    await (_db.update(_db.area)..where((t) => t.id.equals(id))).write(
      AreaCompanion(activo: Value(activo), updatedAt: Value(DateTime.now())),
    );
    return (_db.select(_db.area)..where((t) => t.id.equals(id))).getSingle();
  }
}
