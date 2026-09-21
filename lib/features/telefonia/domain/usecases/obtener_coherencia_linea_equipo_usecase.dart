import '../coherencia_linea_equipo.dart';
import '../repositories/asignacion_linea_telefonica_repository.dart';
import '../repositories/linea_telefonica_equipo_repository.dart';

/// Resuelve [evaluarCoherenciaLineaEquipo] contra los datos reales:
/// asignación vigente de la línea + equipo vigente + custodia vigente de
/// ese equipo en Inventario.
///
/// Es el único sitio que hace esas tres lecturas. Las guardias de los
/// casos de uso y la pantalla del expediente lo usan, para que no
/// existan dos opiniones sobre si una línea está coherente.
class ObtenerCoherenciaLineaEquipoUseCase {
  ObtenerCoherenciaLineaEquipoUseCase(this._equipoRepository, this._asignacionRepository);

  final LineaTelefonicaEquipoRepository _equipoRepository;
  final AsignacionLineaTelefonicaRepository _asignacionRepository;

  Future<CoherenciaLineaEquipo> ejecutar(String lineaTelefonicaId) async {
    final equipo = await _equipoRepository.obtenerActualPorLinea(lineaTelefonicaId);
    final asignacion = await _asignacionRepository.obtenerActivaPorLinea(lineaTelefonicaId);

    if (equipo == null) {
      return CoherenciaLineaEquipo(
        estado: EstadoCoherenciaLineaEquipo.sinEquipo,
        destinoLinea: destinoDeAsignacionLinea(asignacion),
      );
    }

    final custodia = await _equipoRepository.obtenerCustodiaInventarioActual(equipo.unidadId);
    return evaluarCoherenciaLineaEquipo(
      unidadId: equipo.unidadId,
      destinoLinea: destinoDeAsignacionLinea(asignacion),
      destinoEquipo: destinoDeCustodia(custodia),
      pendienteRecuperacionDesde: custodia?.pendienteRecuperacionDesde,
    );
  }

  /// Todas las líneas de golpe — tres consultas en total, nunca tres por
  /// línea. Las líneas que no aparezcan en [lineaTelefonicaIds] no se
  /// incluyen.
  Future<Map<String, CoherenciaLineaEquipo>> ejecutarPorLineas(
    Iterable<String> lineaTelefonicaIds,
  ) async {
    final ids = lineaTelefonicaIds.toSet();
    if (ids.isEmpty) return const {};

    final equipos = await _equipoRepository.obtenerActualesPorTodasLasLineas();
    final asignaciones = await _asignacionRepository.obtenerActivasPorTodasLasLineas();
    final custodias = await _equipoRepository.obtenerCustodiasInventarioActuales(
      ids.map((id) => equipos[id]?.unidadId).whereType<String>(),
    );

    return {
      for (final id in ids)
        id: evaluarCoherenciaLineaEquipo(
          unidadId: equipos[id]?.unidadId,
          destinoLinea: destinoDeAsignacionLinea(asignaciones[id]),
          destinoEquipo: destinoDeCustodia(custodias[equipos[id]?.unidadId]),
          pendienteRecuperacionDesde: custodias[equipos[id]?.unidadId]?.pendienteRecuperacionDesde,
        ),
    };
  }
}
