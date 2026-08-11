import 'package:riseg_one/core/database/app_database.dart';

/// Custodia real de una unidad en Inventario en este momento, resuelta
/// para Telefonía (Etapa 9B) — usado por la UI para mostrar la
/// advertencia de divergencia (punto 5 de 9B) sin que la pantalla de
/// Telefonía importe el repositorio de Inventario directamente.
class CustodiaInventarioLineaTelefonica {
  const CustodiaInventarioLineaTelefonica({this.empleadoId, this.servicioId});
  final String? empleadoId;
  final String? servicioId;
}

/// Qué teléfono físico de Inventario trae la SIM de una línea, en el
/// tiempo (Etapa 9B) — ver el doc comment de `LineaTelefonicaEquipo`.
///
/// **Decisión de consistencia con Inventario** (memoria del proyecto,
/// confirmada dos veces con Marlon): esta interfaz sí escribe en
/// Inventario cuando corresponde — nunca duplica la custodia (esa sigue
/// viviendo únicamente en `Inventario.Asignacion`), pero compone con el
/// `AsignacionRepository` real de Inventario (mismo patrón que
/// `PagoNominaRepositoryImpl` componiendo `EgresoRepository` de
/// Finanzas) para que, cuando la línea tiene un destino
/// (empleado/Servicio), el equipo asociado quede con la misma custodia
/// en Inventario. Cada método recibe `sincronizarInventario` — la UI
/// (punto 7 de 9B) siempre deja explícito si el usuario quiere mover
/// también el equipo, nunca lo asume.
abstract interface class LineaTelefonicaEquipoRepository {
  Future<LineaTelefonicaEquipoData?> obtenerActualPorLinea(String lineaTelefonicaId);

  /// Historial completo, orden descendente por `fechaInicio`.
  Future<List<LineaTelefonicaEquipoData>> listarPorLinea(String lineaTelefonicaId);

  /// La línea telefónica actual de una unidad, si la tiene — usada
  /// desde el expediente de la unidad en Inventario (punto 12 de 9B,
  /// solo lectura).
  Future<LineaTelefonicaEquipoData?> obtenerActualPorUnidad(String unidadId);

  /// La custodia real de [unidadId] en Inventario en este momento
  /// (`null` si no tiene ninguna asignación activa) — solo lectura,
  /// usada por la UI de Telefonía para la advertencia de divergencia.
  Future<CustodiaInventarioLineaTelefonica?> obtenerCustodiaInventarioActual(String unidadId);

  /// Asocia una unidad a la línea (primera vez, o después de un
  /// retiro). Si [sincronizarInventario] y la línea tiene una
  /// asignación vigente, compone `AsignacionRepository.crear` de
  /// Inventario para mover la custodia de la unidad a ese mismo
  /// destino — sin validar aquí "unidad disponible"/"unidad es
  /// teléfono" (vive en `AsociarEquipoLineaTelefonicaUseCase`).
  Future<LineaTelefonicaEquipoData> asociar({
    required String lineaTelefonicaId,
    required String unidadId,
    required DateTime fechaInicio,
    String? observaciones,
    bool sincronizarInventario = true,
    String? actor,
  });

  /// Cierra el equipo vigente de la línea, sin reemplazo. Si
  /// [sincronizarInventario], compone el cierre de la custodia en
  /// Inventario — **solo si** la asignación activa de la unidad en
  /// Inventario todavía coincide con el destino de la línea (guardia de
  /// divergencia: nunca pisa una reasignación hecha directo en
  /// Inventario).
  Future<void> retirar({
    required String lineaTelefonicaId,
    required DateTime fechaFin,
    bool sincronizarInventario = true,
    String? actor,
  });

  /// Cierra el equipo vigente (con la misma guardia de divergencia que
  /// [retirar]) y asocia uno nuevo (con la misma composición que
  /// [asociar]) — una sola operación.
  Future<LineaTelefonicaEquipoData> cambiar({
    required String lineaTelefonicaId,
    required String nuevaUnidadId,
    required DateTime fecha,
    String? observaciones,
    bool sincronizarInventario = true,
    String? actor,
  });

  /// Cierra el equipo vigente de la línea (si existe) liberando siempre
  /// la custodia en Inventario cuando coincide — llamado desde
  /// `LineaTelefonicaRepositoryImpl.darDeBaja` (la línea ya no opera,
  /// el teléfono físico queda disponible para reutilizarse). No-op si
  /// no hay equipo vigente.
  Future<void> cerrarPorBajaLinea({required String lineaTelefonicaId, required DateTime fecha});

  /// Sincroniza la custodia en Inventario del equipo actual (si lo hay)
  /// con la asignación vigente actual de la línea (si la hay) — usado
  /// cuando cambia el destino de la **línea** (Asignar/Cambiar/Retirar
  /// asignación, punto 7 de 9B) y el usuario pidió explícitamente mover
  /// también el equipo. El equipo asociado en sí no cambia — no abre ni
  /// cierra ninguna fila de `LineaTelefonicaEquipo`, solo mueve la
  /// custodia real en Inventario para que coincida con el nuevo destino
  /// de la línea (o la libera, si la línea se quedó sin destino).
  Future<void> sincronizarConAsignacionVigente({required String lineaTelefonicaId, required DateTime fecha});
}
