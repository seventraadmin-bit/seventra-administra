import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/asignacion_linea_telefonica_repository.dart';
import '../repositories/linea_telefonica_equipo_repository.dart';

sealed class CambiarAsignacionLineaTelefonicaResultado {}

class CambiarAsignacionLineaTelefonicaExitoso extends CambiarAsignacionLineaTelefonicaResultado {
  CambiarAsignacionLineaTelefonicaExitoso(this.nuevaAsignacion);
  final AsignacionLineaTelefonicaData nuevaAsignacion;
}

class CambiarAsignacionLineaTelefonicaNoExiste extends CambiarAsignacionLineaTelefonicaResultado {}

class CambiarAsignacionLineaTelefonicaYaCerrada extends CambiarAsignacionLineaTelefonicaResultado {}

/// Exactamente uno del nuevo empleado/servicio debe venir poblado.
class CambiarAsignacionLineaTelefonicaDestinoInvalido extends CambiarAsignacionLineaTelefonicaResultado {}

class CambiarAsignacionLineaTelefonicaErrorInesperado extends CambiarAsignacionLineaTelefonicaResultado {
  CambiarAsignacionLineaTelefonicaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// "Cambiar asignación" (Etapa 9B, punto 3) — cierra la vigente (motivo
/// `cambioResponsable`, automático) y crea la nueva, una sola
/// operación. Si [moverEquipoAsociado] (default `true`) y la línea
/// tiene un equipo asociado, sincroniza su custodia en Inventario hacia
/// el nuevo destino — la UI siempre expone esta opción de forma
/// explícita (punto 7: "no quiero automatismos sorprendentes").
class CambiarAsignacionLineaTelefonicaUseCase {
  CambiarAsignacionLineaTelefonicaUseCase(this._asignacionRepository, this._equipoRepository);

  final AsignacionLineaTelefonicaRepository _asignacionRepository;
  final LineaTelefonicaEquipoRepository _equipoRepository;

  Future<CambiarAsignacionLineaTelefonicaResultado> ejecutar({
    required String asignacionLineaTelefonicaActualId,
    required DateTime fecha,
    String? observacionesTermino,
    String? nuevoEmpleadoId,
    String? nuevoServicioId,
    String? observacionesNueva,
    bool moverEquipoAsociado = true,
    String? actorUsuarioId,
  }) async {
    if ((nuevoEmpleadoId == null) == (nuevoServicioId == null)) {
      return CambiarAsignacionLineaTelefonicaDestinoInvalido();
    }

    final actual = await _asignacionRepository.obtenerPorId(asignacionLineaTelefonicaActualId);
    if (actual == null) return CambiarAsignacionLineaTelefonicaNoExiste();
    if (actual.fechaTermino != null) return CambiarAsignacionLineaTelefonicaYaCerrada();

    try {
      final nueva = await _asignacionRepository.cambiarResponsable(
        asignacionLineaTelefonicaActualId: asignacionLineaTelefonicaActualId,
        fecha: fecha,
        observacionesTermino: observacionesTermino,
        nuevoEmpleadoId: nuevoEmpleadoId,
        nuevoServicioId: nuevoServicioId,
        observacionesNueva: observacionesNueva,
        actorUsuarioId: actorUsuarioId,
      );

      if (moverEquipoAsociado) {
        await _equipoRepository.sincronizarConAsignacionVigente(
          lineaTelefonicaId: actual.lineaTelefonicaId,
          fecha: fecha,
        );
      }

      return CambiarAsignacionLineaTelefonicaExitoso(nueva);
    } catch (e) {
      return CambiarAsignacionLineaTelefonicaErrorInesperado(e.toString());
    }
  }
}
