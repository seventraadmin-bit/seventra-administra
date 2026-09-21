import 'package:riseg_one/core/database/app_database.dart';

/// Custodia real de una unidad en Inventario en este momento, resuelta
/// para Telefonía (Etapa 9B) — usado por la UI para mostrar la
/// advertencia de divergencia (punto 5 de 9B) sin que la pantalla de
/// Telefonía importe el repositorio de Inventario directamente.
class CustodiaInventarioLineaTelefonica {
  const CustodiaInventarioLineaTelefonica({
    this.empleadoId,
    this.servicioId,
    this.pendienteRecuperacionDesde,
  });

  final String? empleadoId;
  final String? servicioId;

  /// Marca REAL de Inventario (v82/v83): alguien declaró en la
  /// conciliación de baja que el bien sigue en manos de la persona que
  /// se fue. No es una bandera de confianza ni un texto — se pone
  /// únicamente por decisión documentada.
  ///
  /// Cambia el SIGNIFICADO de que la línea esté sin asignar: no es un
  /// dato corrupto, son dos ciclos de vida distintos avanzando a su
  /// ritmo.
  final DateTime? pendienteRecuperacionDesde;
}

/// Qué teléfono físico de Inventario trae la SIM de una línea, en el
/// tiempo (Etapa 9B) — ver el doc comment de `LineaTelefonicaEquipo`.
///
/// **Nunca escribe en Inventario** (Rebanada 2). Hasta aquí esta
/// interfaz sí lo hacía: cada método llevaba `sincronizarInventario` y
/// componía `AsignacionRepository.crear`/`cerrar` para mover la
/// custodia del aparato al destino de la línea. Se retiró — le daba a
/// Telefonía autoridad sobre la custodia física y escribía por debajo
/// de los casos de uso de Inventario, sin sus validaciones ni sus
/// permisos. Asociar, cambiar o retirar un equipo es hoy
/// exclusivamente una operación telefónica.
///
/// La coherencia se mantiene por el otro lado: los casos de uso de
/// Telefonía rechazan antes de persistir lo que dejaría la línea en
/// contradicción con la custodia, y cuando Inventario mueve la
/// custodia la asignación de la línea la sigue
/// (`LineaTelefonicaDeUnidad`).
abstract interface class LineaTelefonicaEquipoRepository {
  Future<LineaTelefonicaEquipoData?> obtenerActualPorLinea(String lineaTelefonicaId);

  /// `lineaTelefonicaId` → su equipo actual, para todas las líneas que
  /// tienen uno — Etapa 12C (Reportes): "líneas sin equipo" se deriva
  /// de las líneas cuyo id no aparece aquí, sin N+1. Mismo patrón que
  /// `RecargaLineaTelefonicaRepository.obtenerUltimasPorTodasLasLineas`.
  Future<Map<String, LineaTelefonicaEquipoData>> obtenerActualesPorTodasLasLineas();

  /// Historial completo, orden descendente por `fechaInicio`.
  Future<List<LineaTelefonicaEquipoData>> listarPorLinea(String lineaTelefonicaId);

  /// La línea telefónica actual de una unidad, si la tiene — usada
  /// desde el expediente de la unidad en Inventario (punto 12 de 9B,
  /// solo lectura).
  Future<LineaTelefonicaEquipoData?> obtenerActualPorUnidad(String unidadId);

  /// Historial completo de líneas que ha tenido una unidad, orden
  /// descendente por `fechaInicio` (Etapa 9D) — el reverso de
  /// [listarPorLinea].
  Future<List<LineaTelefonicaEquipoData>> listarPorUnidad(String unidadId);

  /// La custodia real de [unidadId] en Inventario en este momento
  /// (`null` si no tiene ninguna asignación activa) — SOLO LECTURA.
  Future<CustodiaInventarioLineaTelefonica?> obtenerCustodiaInventarioActual(String unidadId);

  /// La custodia real de varias unidades en UNA consulta — para
  /// listados que muestran coherencia sin resolver fila por fila. Las
  /// unidades sin custodia activa simplemente no aparecen en el mapa.
  Future<Map<String, CustodiaInventarioLineaTelefonica>> obtenerCustodiasInventarioActuales(
    Iterable<String> unidadIds,
  );

  /// Asocia una unidad a la línea (primera vez, o después de un
  /// retiro). No valida "unidad disponible"/"unidad es teléfono"/
  /// coherencia con la custodia: eso vive en
  /// `AsociarEquipoLineaTelefonicaUseCase`.
  ///
  /// `alinearLineaCon…`: si vienen poblados y la línea no tiene
  /// asignación vigente, se le crea una a ese destino en la MISMA
  /// transacción — es la línea siguiendo a la custodia que el aparato
  /// ya tiene en Inventario (§7). Jamás escribe en Inventario.
  Future<LineaTelefonicaEquipoData> asociar({
    required String lineaTelefonicaId,
    required String unidadId,
    required DateTime fechaInicio,
    String? observaciones,
    String? alinearLineaConEmpleadoId,
    String? alinearLineaConServicioId,
    String? actorUsuarioId,
  });

  /// Cierra el equipo vigente de la línea, sin reemplazo. **No toca la
  /// custodia en Inventario**: retirar un equipo de una línea no
  /// devuelve físicamente el aparato, sólo lo desvincula.
  Future<void> retirar({
    required String lineaTelefonicaId,
    required DateTime fechaFin,
    String? actorUsuarioId,
  });

  /// Cierra el equipo vigente y asocia uno nuevo — una sola operación,
  /// ninguna de las dos toca la custodia. `alinearLineaCon…` funciona
  /// igual que en [asociar].
  Future<LineaTelefonicaEquipoData> cambiar({
    required String lineaTelefonicaId,
    required String nuevaUnidadId,
    required DateTime fecha,
    String? observaciones,
    String? alinearLineaConEmpleadoId,
    String? alinearLineaConServicioId,
    String? actorUsuarioId,
  });

  /// Cierra el equipo vigente de la línea (si existe) — llamado desde
  /// `LineaTelefonicaRepositoryImpl.darDeBaja`. La línea ya no opera,
  /// pero el aparato sigue donde Inventario diga. No-op si no hay
  /// equipo vigente.
  Future<void> cerrarPorBajaLinea({required String lineaTelefonicaId, required DateTime fecha});
}
