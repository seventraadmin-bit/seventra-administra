import 'package:riseg_one/core/database/app_database.dart';

import '../usecases/eliminar_categoria_financiera_fisicamente_usecase.dart';

/// Catálogo administrable de categorías financieras (Etapa 4K.1) —
/// nace vacío, RISEG lo captura desde una pantalla propia. `archivar`
/// mueve `cicloVidaRegistro` a `archivado`, nunca borra la fila; la
/// única forma de borrado real es `eliminarFisicamente` (Etapa 18,
/// extraordinaria, exclusiva del Usuario Maestro), y solo si ningún
/// Ingreso/Egreso la referencia.
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

  Future<CategoriaFinancieraData> actualizar({
    required String id,
    required String codigo,
    required String nombre,
    required String tipo,
    required String tipoMovimiento,
  });

  Future<CategoriaFinancieraData> archivar(String id);

  /// Resumen de solo lectura de elegibilidad para eliminación física —
  /// `detalleBloqueo` no nulo si algún Ingreso/Egreso real la
  /// referencia (`categoriaFinancieraId`, `onDelete: restrict`).
  Future<ResumenEliminacionCategoriaFinanciera> obtenerResumenEliminacionFisica(String categoriaFinancieraId);

  Future<EliminarCategoriaFinancieraFisicamenteResultado> eliminarFisicamente({
    required String categoriaFinancieraId,
    required String motivo,
    String? actorUsuarioId,
  });
}
