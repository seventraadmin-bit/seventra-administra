import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/tables/categoria_articulo_table.dart' show AplicacionEspecializadaCategoriaArticulo;

import '../../domain/repositories/categoria_articulo_repository.dart';
import '../../domain/usecases/eliminar_categoria_articulo_fisicamente_usecase.dart';

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
  Future<CategoriaArticuloData> crear({
    required String nombre,
    AplicacionEspecializadaCategoriaArticulo? aplicacionEspecializada,
  }) {
    return _db.into(_db.categoriaArticulo).insertReturning(
          CategoriaArticuloCompanion.insert(
            nombre: nombre,
            aplicacionEspecializada: Value(aplicacionEspecializada?.name),
          ),
        );
  }

  @override
  Future<CategoriaArticuloData> actualizar({
    required String id,
    String? nombre,
    AplicacionEspecializadaCategoriaArticulo? aplicacionEspecializada,
    bool limpiarAplicacionEspecializada = false,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.categoriaArticulo)..where((t) => t.id.equals(id))).write(
        CategoriaArticuloCompanion(
          nombre: nombre == null ? const Value.absent() : Value(nombre),
          aplicacionEspecializada: limpiarAplicacionEspecializada
              ? const Value(null)
              : (aplicacionEspecializada == null ? const Value.absent() : Value(aplicacionEspecializada.name)),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return (_db.select(_db.categoriaArticulo)..where((t) => t.id.equals(id))).getSingle();
    });
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

  /// Eliminación física extraordinaria (Etapa 11D) — condición exacta
  /// acordada con Marlon: elegible solo si ninguna fila de `Articulo`
  /// referencia esta Categoría vía `categoriaId`. Todo — validación,
  /// snapshot, registro de auditoría y `DELETE` — ocurre en una sola
  /// transacción; nunca `CASCADE`.
  @override
  Future<EliminarCategoriaArticuloFisicamenteResultado> eliminarFisicamente({
    required String categoriaArticuloId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final categoria =
          await (_db.select(_db.categoriaArticulo)..where((t) => t.id.equals(categoriaArticuloId))).getSingleOrNull();
      if (categoria == null) return EliminarCategoriaArticuloFisicamenteNoExiste();

      final articulos =
          await (_db.select(_db.articulo)..where((t) => t.categoriaId.equals(categoriaArticuloId))).get();
      if (articulos.isNotEmpty) {
        return EliminarCategoriaArticuloFisicamenteTieneDependencias(
          'Tiene ${articulos.length} artículo(s) registrado(s).',
        );
      }

      await _db.into(_db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'categoriaArticulo',
              entidadIdOriginal: categoriaArticuloId,
              fechaHora: DateTime.now(),
              motivo: motivo,
              snapshotJson: jsonEncode(categoria.toJson()),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );
      await (_db.delete(_db.categoriaArticulo)..where((t) => t.id.equals(categoriaArticuloId))).go();

      return EliminarCategoriaArticuloFisicamenteExitoso();
    });
  }
}
