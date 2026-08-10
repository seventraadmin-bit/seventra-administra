import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/categoria_articulo_repository.dart';

class CategoriaArticuloRepositoryImpl implements CategoriaArticuloRepository {
  CategoriaArticuloRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<CategoriaArticuloData?> obtenerPorId(String id) {
    return (_db.select(_db.categoriaArticulo)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<CategoriaArticuloData>> listar() {
    return (_db.select(_db.categoriaArticulo)
          ..where((t) => t.cicloVidaRegistro.equals('activo'))
          ..orderBy([(t) => OrderingTerm.asc(t.nombre)]))
        .get();
  }

  @override
  Future<CategoriaArticuloData> crear({required String nombre}) {
    return _db.into(_db.categoriaArticulo).insertReturning(
          CategoriaArticuloCompanion.insert(nombre: nombre),
        );
  }

  @override
  Future<CategoriaArticuloData> archivar(String id) {
    return _db.transaction(() async {
      await (_db.update(_db.categoriaArticulo)..where((t) => t.id.equals(id))).write(
        CategoriaArticuloCompanion(
          cicloVidaRegistro: const Value('archivado'),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return (_db.select(_db.categoriaArticulo)..where((t) => t.id.equals(id))).getSingle();
    });
  }
}
