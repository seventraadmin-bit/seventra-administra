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
  Future<PuestoData?> obtenerPorId(String id) {
    return (_db.select(_db.puesto)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<PuestoData>> listarActivos() {
    return (_db.select(_db.puesto)
          ..where((t) => t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name)))
        .get();
  }
}
