import 'package:drift/drift.dart';

import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/linea_telefonica_plan_repository.dart';

class LineaTelefonicaPlanRepositoryImpl implements LineaTelefonicaPlanRepository {
  LineaTelefonicaPlanRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<LineaTelefonicaPlanData?> obtenerVigentePorLinea(String lineaTelefonicaId) {
    return (_db.select(_db.lineaTelefonicaPlan)
          ..where((t) => t.lineaTelefonicaId.equals(lineaTelefonicaId) & t.fechaFinVigencia.isNull()))
        .getSingleOrNull();
  }

  @override
  Future<List<LineaTelefonicaPlanData>> listarPorLinea(String lineaTelefonicaId) {
    return (_db.select(_db.lineaTelefonicaPlan)
          ..where((t) => t.lineaTelefonicaId.equals(lineaTelefonicaId))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaInicioVigencia)]))
        .get();
  }

  @override
  Future<List<LineaTelefonicaPlanData>> listarVigentes() {
    return (_db.select(_db.lineaTelefonicaPlan)..where((t) => t.fechaFinVigencia.isNull())).get();
  }

  @override
  Future<LineaTelefonicaPlanData> cambiarPlan({
    required String lineaTelefonicaId,
    required String nombre,
    required int costoMensual,
    required DateTime fechaInicioVigencia,
    DateTime? fechaFinPermanencia,
    String? observaciones,
  }) {
    return _db.transaction(() async {
      final vigente = await obtenerVigentePorLinea(lineaTelefonicaId);
      if (vigente != null) {
        await (_db.update(_db.lineaTelefonicaPlan)..where((t) => t.id.equals(vigente.id))).write(
          LineaTelefonicaPlanCompanion(
            fechaFinVigencia: Value(fechaInicioVigencia.subtract(const Duration(days: 1))),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }

      return _db.into(_db.lineaTelefonicaPlan).insertReturning(
            LineaTelefonicaPlanCompanion.insert(
              lineaTelefonicaId: lineaTelefonicaId,
              nombre: nombre,
              costoMensual: costoMensual,
              fechaInicioVigencia: fechaInicioVigencia,
              fechaFinPermanencia: Value(fechaFinPermanencia),
              observaciones: Value(observaciones),
            ),
          );
    });
  }
}
