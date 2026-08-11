import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/tables/categoria_articulo_table.dart' show AplicacionEspecializadaCategoriaArticulo;

import '../usecases/eliminar_categoria_articulo_fisicamente_usecase.dart';

/// Catálogo administrable de categorías de artículo (Etapa 7A) — nace
/// vacío, RISEG lo captura desde una pantalla propia. Sin eliminación
/// física ordinaria: `archivar` mueve `cicloVidaRegistro` a
/// `archivado`, nunca borra la fila — la única excepción es
/// [eliminarFisicamente] (Etapa 11D), facultad extraordinaria del
/// Usuario Maestro.
abstract interface class CategoriaArticuloRepository {
  Future<CategoriaArticuloData?> obtenerPorId(String id);

  /// Solo `cicloVidaRegistro == activo` — mismo criterio que cualquier
  /// otro listado de catálogo del proyecto.
  Future<List<CategoriaArticuloData>> listar();

  Future<CategoriaArticuloData> crear({
    required String nombre,
    AplicacionEspecializadaCategoriaArticulo? aplicacionEspecializada,
  });

  /// Edición (Etapa 9D, ajuste posterior) — nombre y/o clasificación de
  /// aplicación especializada. [limpiarAplicacionEspecializada] permite
  /// volver la categoría a genérica (`null`) explícitamente, ya que
  /// pasar `aplicacionEspecializada: null` por sí solo significaría
  /// "no tocar este campo" (mismo criterio `limpiarX` ya usado en
  /// `ArticuloRepository.corregir`).
  Future<CategoriaArticuloData> actualizar({
    required String id,
    String? nombre,
    AplicacionEspecializadaCategoriaArticulo? aplicacionEspecializada,
    bool limpiarAplicacionEspecializada = false,
  });

  Future<CategoriaArticuloData> archivar(String id);

  /// Eliminación física extraordinaria (Etapa 11D) — ver el doc comment
  /// de la implementación para las condiciones exactas.
  Future<EliminarCategoriaArticuloFisicamenteResultado> eliminarFisicamente({
    required String categoriaArticuloId,
    required String motivo,
    String? actorUsuarioId,
  });
}
