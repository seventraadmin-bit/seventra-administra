import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/categoria_financiera_repository.dart';

class CategoriaFinancieraRepositoryImpl implements CategoriaFinancieraRepository {
  CategoriaFinancieraRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<CategoriaFinancieraData?> obtenerPorId(String id) {
    return (_db.select(_db.categoriaFinanciera)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<CategoriaFinancieraData>> listar({String? tipo}) {
    final query = _db.select(_db.categoriaFinanciera)..where((t) => t.cicloVidaRegistro.equals('activo'));
    if (tipo != null) {
      query.where((t) => t.tipo.equals(tipo) | t.tipo.equals('ambos'));
    }
    query.orderBy([(t) => OrderingTerm.asc(t.nombre)]);
    return query.get();
  }

  @override
  Future<CategoriaFinancieraData> crear({
    required String codigo,
    required String nombre,
    required String tipo,
    required String tipoMovimiento,
  }) {
    return _db.into(_db.categoriaFinanciera).insertReturning(
          CategoriaFinancieraCompanion.insert(
            codigo: codigo,
            nombre: nombre,
            tipo: tipo,
            tipoMovimiento: tipoMovimiento,
          ),
        );
  }

  @override
  Future<CategoriaFinancieraData> archivar(String id) {
    return _db.transaction(() async {
      await (_db.update(_db.categoriaFinanciera)..where((t) => t.id.equals(id))).write(
        CategoriaFinancieraCompanion(
          cicloVidaRegistro: const Value('archivado'),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return (_db.select(_db.categoriaFinanciera)..where((t) => t.id.equals(id))).getSingle();
    });
  }
}
