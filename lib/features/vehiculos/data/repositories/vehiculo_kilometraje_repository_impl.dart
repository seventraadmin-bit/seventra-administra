import 'package:drift/drift.dart';

import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/vehiculo_kilometraje_repository.dart';

class VehiculoKilometrajeRepositoryImpl implements VehiculoKilometrajeRepository {
  VehiculoKilometrajeRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<VehiculoKilometrajeData?> obtenerActual(String vehiculoId) {
    return (_db.select(_db.vehiculoKilometraje)
          ..where((t) => t.vehiculoId.equals(vehiculoId))
          ..orderBy([(t) => OrderingTerm.desc(t.fecha), (t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  @override
  Future<List<VehiculoKilometrajeData>> listarPorVehiculo(String vehiculoId) {
    return (_db.select(_db.vehiculoKilometraje)
          ..where((t) => t.vehiculoId.equals(vehiculoId))
          ..orderBy([(t) => OrderingTerm.desc(t.fecha), (t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  @override
  Future<List<VehiculoKilometrajeData>> listarTodos() {
    return (_db.select(_db.vehiculoKilometraje)
          ..orderBy([(t) => OrderingTerm.desc(t.fecha), (t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  @override
  Future<VehiculoKilometrajeData> registrar({
    required String vehiculoId,
    required DateTime fecha,
    required int kilometraje,
    required String origen,
    String? observaciones,
    String? actor,
  }) {
    return _db.into(_db.vehiculoKilometraje).insertReturning(
          VehiculoKilometrajeCompanion.insert(
            vehiculoId: vehiculoId,
            fecha: fecha,
            kilometraje: kilometraje,
            origen: origen,
            observaciones: Value(observaciones),
            actor: Value(actor),
          ),
        );
  }
}
