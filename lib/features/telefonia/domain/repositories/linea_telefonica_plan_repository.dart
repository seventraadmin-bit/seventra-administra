import 'package:riseg_one/core/database/app_database.dart';

/// Plan/costo de una línea telefónica (Etapa 9A) — ver el doc comment
/// de `LineaTelefonicaPlan` para el criterio de diseño completo
/// (variante simplificada de vigencia, sin programación futura).
abstract interface class LineaTelefonicaPlanRepository {
  /// El plan vigente — `fechaFinVigencia IS NULL`. `null` si la línea
  /// nunca ha tenido un plan capturado.
  Future<LineaTelefonicaPlanData?> obtenerVigentePorLinea(String lineaTelefonicaId);

  /// Historial completo, orden descendente por `fechaInicioVigencia`.
  Future<List<LineaTelefonicaPlanData>> listarPorLinea(String lineaTelefonicaId);

  /// Todos los planes vigentes (`fechaFinVigencia IS NULL`) de todas las
  /// líneas, sin acotar — consulta masiva de una sola vez (evita N+1),
  /// mismo criterio que `VehiculoDocumentoRepository.listarTodos`. Útil
  /// para el resumen de costos de la Etapa 9C.
  Future<List<LineaTelefonicaPlanData>> listarVigentes();

  /// Cierra el plan vigente (si existe) e inserta uno nuevo, en una sola
  /// transacción — "cambiar plan" siempre pasa por aquí, tanto para el
  /// primer plan de una línea (nada que cerrar) como para un cambio de
  /// precio posterior.
  Future<LineaTelefonicaPlanData> cambiarPlan({
    required String lineaTelefonicaId,
    required String nombre,
    required int costoMensual,
    required DateTime fechaInicioVigencia,
    DateTime? fechaFinPermanencia,
    String? observaciones,
  });
}
