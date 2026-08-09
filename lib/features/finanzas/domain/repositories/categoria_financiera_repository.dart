import 'package:riseg_one/core/database/app_database.dart';

/// Catálogo administrable de categorías financieras (Etapa 4K.1) —
/// nace vacío, RISEG lo captura desde una pantalla propia. Sin
/// eliminación física: `archivar` mueve `cicloVidaRegistro` a
/// `archivado`, nunca borra la fila.
abstract interface class CategoriaFinancieraRepository {
  Future<CategoriaFinancieraData?> obtenerPorId(String id);

  /// Solo `cicloVidaRegistro == activo` — mismo criterio que cualquier
  /// otro listado de catálogo del proyecto.
  Future<List<CategoriaFinancieraData>> listar({String? tipo});

  Future<CategoriaFinancieraData> crear({
    required String codigo,
    required String nombre,
    required String tipo,
    required String tipoMovimiento,
  });

  Future<CategoriaFinancieraData> archivar(String id);
}
