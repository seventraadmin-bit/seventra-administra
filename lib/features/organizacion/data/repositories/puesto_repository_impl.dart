import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import '../../domain/repositories/puesto_repository.dart';

class PuestoRepositoryImpl implements PuestoRepository {
  PuestoRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<PuestoData> crear(PuestoCompanion datos) {
    return _db.into(_db.puesto).insertReturning(datos);
  }

  @override
  Future<PuestoData> actualizar({required String id, required PuestoCompanion cambios}) async {
    await (_db.update(_db.puesto)..where((t) => t.id.equals(id))).write(
      cambios.copyWith(updatedAt: Value(DateTime.now())),
    );
    return (_db.select(_db.puesto)..where((t) => t.id.equals(id))).getSingle();
  }

  @override
  Future<PuestoData?> obtenerPorId(String id) {
    return (_db.select(_db.puesto)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<PuestoData>> listarActivos() {
    return (_db.select(_db.puesto)
          ..where((t) => t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name)))
        .get();
  }

  @override
  Future<PuestoData> cambiarCicloVida({required String id, required CicloVidaRegistro nuevo}) async {
    await (_db.update(_db.puesto)..where((t) => t.id.equals(id))).write(
      PuestoCompanion(cicloVidaRegistro: Value(nuevo.name), updatedAt: Value(DateTime.now())),
    );
    return (_db.select(_db.puesto)..where((t) => t.id.equals(id))).getSingle();
  }

  @override
  Future<int> contarActivosPorArea(String areaId) async {
    final conteo = _db.puesto.id.count();
    final query = _db.selectOnly(_db.puesto)
      ..addColumns([conteo])
      ..where(
        _db.puesto.areaId.equals(areaId) &
            _db.puesto.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
      );
    final fila = await query.getSingle();
    return fila.read(conteo) ?? 0;
  }
}
