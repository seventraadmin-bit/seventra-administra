import '../repositories/linea_telefonica_equipo_repository.dart';

sealed class RetirarEquipoLineaTelefonicaResultado {}

class RetirarEquipoLineaTelefonicaExitoso extends RetirarEquipoLineaTelefonicaResultado {}

/// La línea no tiene equipo vigente que retirar.
class RetirarEquipoLineaTelefonicaSinEquipoVigente extends RetirarEquipoLineaTelefonicaResultado {}

class RetirarEquipoLineaTelefonicaErrorInesperado extends RetirarEquipoLineaTelefonicaResultado {
  RetirarEquipoLineaTelefonicaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Retira el teléfono asociado a una línea sin reemplazo (Etapa 9B) —
/// libera también la custodia en Inventario si coincide con el destino
/// actual de la línea (guardia de divergencia, ver el doc comment de
/// `LineaTelefonicaEquipoRepository`). La línea queda sin equipo, algo
/// completamente válido.
class RetirarEquipoLineaTelefonicaUseCase {
  RetirarEquipoLineaTelefonicaUseCase(this._equipoRepository);

  final LineaTelefonicaEquipoRepository _equipoRepository;

  Future<RetirarEquipoLineaTelefonicaResultado> ejecutar({
    required String lineaTelefonicaId,
    required DateTime fechaFin,
    String? actorUsuarioId,
  }) async {
    final equipoVigente = await _equipoRepository.obtenerActualPorLinea(lineaTelefonicaId);
    if (equipoVigente == null) return RetirarEquipoLineaTelefonicaSinEquipoVigente();

    try {
      await _equipoRepository.retirar(lineaTelefonicaId: lineaTelefonicaId, fechaFin: fechaFin, actorUsuarioId: actorUsuarioId);
      return RetirarEquipoLineaTelefonicaExitoso();
    } catch (e) {
      return RetirarEquipoLineaTelefonicaErrorInesperado(e.toString());
    }
  }
}
