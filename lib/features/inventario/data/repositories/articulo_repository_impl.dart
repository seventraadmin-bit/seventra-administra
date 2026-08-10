import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/articulo_repository.dart';

class ArticuloRepositoryImpl implements ArticuloRepository {
  ArticuloRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<ArticuloData?> obtenerPorId(String id) {
    return (_db.select(_db.articulo)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<ArticuloData>> listar({String? categoriaId, bool soloActivos = true}) {
    final query = _db.select(_db.articulo);
    if (soloActivos) query.where((t) => t.cicloVidaRegistro.equals('activo'));
    if (categoriaId != null) query.where((t) => t.categoriaId.equals(categoriaId));
    query.orderBy([(t) => OrderingTerm.asc(t.nombre)]);
    return query.get();
  }

  @override
  Future<ArticuloData> crear({
    required String folio,
    required String categoriaId,
    required String nombre,
    String? descripcion,
    String? unidadMedida,
    required bool manejaVariante,
    required bool manejaSerie,
    int? costoReferencia,
  }) {
    return _db.into(_db.articulo).insertReturning(
          ArticuloCompanion.insert(
            folio: folio,
            categoriaId: categoriaId,
            nombre: nombre,
            descripcion: Value(descripcion),
            unidadMedida: Value(unidadMedida),
            manejaVariante: Value(manejaVariante),
            manejaSerie: Value(manejaSerie),
            costoReferencia: Value(costoReferencia),
          ),
        );
  }

  @override
  Future<ArticuloData> corregir({
    required String articuloId,
    String? categoriaId,
    String? nombre,
    String? descripcion,
    String? unidadMedida,
    int? costoReferencia,
    bool limpiarDescripcion = false,
    bool limpiarCostoReferencia = false,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.articulo)..where((t) => t.id.equals(articuloId))).write(
        ArticuloCompanion(
          categoriaId: categoriaId == null ? const Value.absent() : Value(categoriaId),
          nombre: nombre == null ? const Value.absent() : Value(nombre),
          descripcion: limpiarDescripcion
              ? const Value(null)
              : (descripcion == null ? const Value.absent() : Value(descripcion)),
          unidadMedida: unidadMedida == null ? const Value.absent() : Value(unidadMedida),
          costoReferencia: limpiarCostoReferencia
              ? const Value(null)
              : (costoReferencia == null ? const Value.absent() : Value(costoReferencia)),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return (_db.select(_db.articulo)..where((t) => t.id.equals(articuloId))).getSingle();
    });
  }

  @override
  Future<ArticuloData> archivar(String articuloId) {
    return _db.transaction(() async {
      await (_db.update(_db.articulo)..where((t) => t.id.equals(articuloId))).write(
        ArticuloCompanion(cicloVidaRegistro: const Value('archivado'), updatedAt: Value(DateTime.now())),
      );
      return (_db.select(_db.articulo)..where((t) => t.id.equals(articuloId))).getSingle();
    });
  }

  @override
  Future<List<ArticuloVarianteData>> listarVariantes(String articuloId, {bool soloActivas = true}) {
    final query = _db.select(_db.articuloVariante)..where((t) => t.articuloId.equals(articuloId));
    if (soloActivas) query.where((t) => t.cicloVidaRegistro.equals('activo'));
    query.orderBy([(t) => OrderingTerm.asc(t.valor)]);
    return query.get();
  }

  @override
  Future<ArticuloVarianteData> crearVariante({required String articuloId, required String valor}) {
    return _db.into(_db.articuloVariante).insertReturning(
          ArticuloVarianteCompanion.insert(articuloId: articuloId, valor: valor),
        );
  }

  @override
  Future<ArticuloVarianteData> archivarVariante(String varianteId) {
    return _db.transaction(() async {
      await (_db.update(_db.articuloVariante)..where((t) => t.id.equals(varianteId))).write(
        ArticuloVarianteCompanion(cicloVidaRegistro: const Value('archivado'), updatedAt: Value(DateTime.now())),
      );
      return (_db.select(_db.articuloVariante)..where((t) => t.id.equals(varianteId))).getSingle();
    });
  }
}
