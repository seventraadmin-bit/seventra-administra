import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/asignacion_linea_telefonica_table.dart' show MotivoTerminoAsignacionLineaTelefonica;
import '../repositories/asignacion_linea_telefonica_repository.dart';
import '../repositories/linea_telefonica_equipo_repository.dart';

sealed class RetirarAsignacionLineaTelefonicaResultado {}

class RetirarAsignacionLineaTelefonicaExitoso extends RetirarAsignacionLineaTelefonicaResultado {
  RetirarAsignacionLineaTelefonicaExitoso(this.asignacion);
  final AsignacionLineaTelefonicaData asignacion;
}

class RetirarAsignacionLineaTelefonicaNoExiste extends RetirarAsignacionLineaTelefonicaResultado {}

class RetirarAsignacionLineaTelefonicaYaCerrada extends RetirarAsignacionLineaTelefonicaResultado {}

class RetirarAsignacionLineaTelefonicaErrorInesperado extends RetirarAsignacionLineaTelefonicaResultado {
  RetirarAsignacionLineaTelefonicaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Libera una línea telefónica (Etapa 9B) — cierra la asignación
/// vigente con motivo `liberacion`. Si [moverEquipoAsociado] (default
/// `true`) y la línea tiene un equipo asociado, libera también su
/// custodia en Inventario (queda `disponible` para reutilizarse) — la
/// UI siempre expone esta opción de forma explícita.
class RetirarAsignacionLineaTelefonicaUseCase {
  RetirarAsignacionLineaTelefonicaUseCase(this._asignacionRepository, this._equipoRepository);

  final AsignacionLineaTelefonicaRepository _asignacionRepository;
  final LineaTelefonicaEquipoRepository _equipoRepository;

  Future<RetirarAsignacionLineaTelefonicaResultado> ejecutar({
    required String asignacionLineaTelefonicaId,
    required DateTime fechaTermino,
    String? observacionesTermino,
    bool moverEquipoAsociado = true,
    String? actor,
  }) async {
    final actual = await _asignacionRepository.obtenerPorId(asignacionLineaTelefonicaId);
    if (actual == null) return RetirarAsignacionLineaTelefonicaNoExiste();
    if (actual.fechaTermino != null) return RetirarAsignacionLineaTelefonicaYaCerrada();

    try {
      final cerrada = await _asignacionRepository.cerrar(
        asignacionLineaTelefonicaId: asignacionLineaTelefonicaId,
        fechaTermino: fechaTermino,
        motivoTermino: MotivoTerminoAsignacionLineaTelefonica.liberacion.name,
        observacionesTermino: observacionesTermino,
        actor: actor,
      );

      if (moverEquipoAsociado) {
        await _equipoRepository.sincronizarConAsignacionVigente(
          lineaTelefonicaId: actual.lineaTelefonicaId,
          fecha: fechaTermino,
        );
      }

      return RetirarAsignacionLineaTelefonicaExitoso(cerrada);
    } catch (e) {
      return RetirarAsignacionLineaTelefonicaErrorInesperado(e.toString());
    }
  }
}
