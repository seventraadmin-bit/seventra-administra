import 'package:riseg_one/core/database/app_database.dart';

/// Catálogo administrable de categorías de artículo (Etapa 7A) — nace
/// vacío, RISEG lo captura desde una pantalla propia. Sin eliminación
/// física: `archivar` mueve `cicloVidaRegistro` a `archivado`, nunca
/// borra la fila.
abstract interface class CategoriaArticuloRepository {
  Future<CategoriaArticuloData?> obtenerPorId(String id);

  /// Solo `cicloVidaRegistro == activo` — mismo criterio que cualquier
  /// otro listado de catálogo del proyecto.
  Future<List<CategoriaArticuloData>> listar();

  Future<CategoriaArticuloData> crear({required String nombre});

  Future<CategoriaArticuloData> archivar(String id);
}
