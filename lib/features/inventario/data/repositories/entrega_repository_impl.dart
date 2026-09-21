import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/entrega_repository.dart';

class EntregaRepositoryImpl implements EntregaRepository {
  EntregaRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<EntregaData?> obtenerPorId(String id) {
    return (_db.select(_db.entrega)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<EntregaData>> listarPorEmpleado(String empleadoId) {
    final query = _db.select(_db.entrega)
      ..where((t) => t.empleadoId.equals(empleadoId))
      ..orderBy([(t) => OrderingTerm.desc(t.fechaEntrega)]);
    return query.get();
  }

  @override
  Future<List<EntregaData>> listarPorServicio(String servicioId) {
    final query = _db.select(_db.entrega)
      ..where((t) => t.servicioId.equals(servicioId))
      ..orderBy([(t) => OrderingTerm.desc(t.fechaEntrega)]);
    return query.get();
  }
}
