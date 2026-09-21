import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../coherencia_linea_equipo.dart';
import '../repositories/asignacion_linea_telefonica_repository.dart';
import '../repositories/linea_telefonica_equipo_repository.dart';
import '../repositories/linea_telefonica_repository.dart';
import 'asignar_linea_telefonica_usecase.dart' show registrarResolucionDeIncoherencia;
import 'obtener_coherencia_linea_equipo_usecase.dart';

sealed class CambiarAsignacionLineaTelefonicaResultado {}

class CambiarAsignacionLineaTelefonicaExitoso extends CambiarAsignacionLineaTelefonicaResultado {
  CambiarAsignacionLineaTelefonicaExitoso(this.nuevaAsignacion);
  final AsignacionLineaTelefonicaData nuevaAsignacion;
}

class CambiarAsignacionLineaTelefonicaNoExiste extends CambiarAsignacionLineaTelefonicaResultado {}

class CambiarAsignacionLineaTelefonicaYaCerrada extends CambiarAsignacionLineaTelefonicaResultado {}

/// Exactamente uno del nuevo empleado/servicio debe venir poblado.
class CambiarAsignacionLineaTelefonicaDestinoInvalido extends CambiarAsignacionLineaTelefonicaResultado {}

/// §11 — el equipo asociado seguiría bajo la custodia anterior. Cambiar
/// sólo la línea dejaría exactamente la contradicción que esta rebanada
/// existe para impedir.
class CambiarAsignacionLineaTelefonicaIncoherenteConEquipo extends CambiarAsignacionLineaTelefonicaResultado {
  CambiarAsignacionLineaTelefonicaIncoherenteConEquipo(this.coherencia);
  final CoherenciaLineaEquipo coherencia;
}

class CambiarAsignacionLineaTelefonicaMotivoRequerido extends CambiarAsignacionLineaTelefonicaResultado {}

class CambiarAsignacionLineaTelefonicaErrorInesperado extends CambiarAsignacionLineaTelefonicaResultado {
  CambiarAsignacionLineaTelefonicaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// "Cambiar asignación" (Etapa 9B, punto 3) — cierra la vigente (motivo
/// `cambioResponsable`, automático) y crea la nueva, una sola
/// operación.
///
/// **Nunca mueve la custodia del equipo** (Rebanada 2): si el teléfono
/// asociado está en manos de A, la línea no puede irse sola a B. Para
/// mover ambos, la operación correcta es transferir el aparato en
/// Inventario — la línea lo sigue automáticamente.
class CambiarAsignacionLineaTelefonicaUseCase {
  CambiarAsignacionLineaTelefonicaUseCase(
    AsignacionLineaTelefonicaRepository asignacionRepository,
    LineaTelefonicaEquipoRepository equipoRepository,
    this._lineaRepository,
  )   : _asignacionRepository = asignacionRepository,
        _coherencia = ObtenerCoherenciaLineaEquipoUseCase(equipoRepository, asignacionRepository);

  final AsignacionLineaTelefonicaRepository _asignacionRepository;
  final LineaTelefonicaRepository _lineaRepository;
  final ObtenerCoherenciaLineaEquipoUseCase _coherencia;

  Future<CambiarAsignacionLineaTelefonicaResultado> ejecutar({
    required String asignacionLineaTelefonicaActualId,
    required DateTime fecha,
    String? observacionesTermino,
    String? nuevoEmpleadoId,
    String? nuevoServicioId,
    String? observacionesNueva,
    String? motivo,
    String? actorUsuarioId,
  }) async {
    if ((nuevoEmpleadoId == null) == (nuevoServicioId == null)) {
      return CambiarAsignacionLineaTelefonicaDestinoInvalido();
    }

    final actual = await _asignacionRepository.obtenerPorId(asignacionLineaTelefonicaActualId);
    if (actual == null) return CambiarAsignacionLineaTelefonicaNoExiste();
    if (actual.fechaTermino != null) return CambiarAsignacionLineaTelefonicaYaCerrada();

    final antes = await _coherencia.ejecutar(actual.lineaTelefonicaId);
    final cambio = CambioAsignacionLinea(
      antes: antes,
      despues: evaluarCoherenciaLineaEquipo(
        unidadId: antes.unidadId,
        destinoLinea: destinoDe(empleadoId: nuevoEmpleadoId, servicioId: nuevoServicioId),
        destinoEquipo: antes.destinoEquipo,
        pendienteRecuperacionDesde: antes.pendienteRecuperacionDesde,
      ),
    );

    if (cambio.dejariaContradiccion) {
      return CambiarAsignacionLineaTelefonicaIncoherenteConEquipo(cambio.despues);
    }
    final esResolucion = cambio.esResolucionDeInconsistencia;
    if (esResolucion && !motivoEsValido(motivo ?? '')) {
      return CambiarAsignacionLineaTelefonicaMotivoRequerido();
    }

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

      if (esResolucion) {
        await registrarResolucionDeIncoherencia(
          lineaRepository: _lineaRepository,
          lineaTelefonicaId: actual.lineaTelefonicaId,
          antes: cambio.antes,
          despues: cambio.despues,
          motivo: motivo!.trim(),
          actorUsuarioId: actorUsuarioId,
        );
      }

      return CambiarAsignacionLineaTelefonicaExitoso(nueva);
    } catch (e) {
      return CambiarAsignacionLineaTelefonicaErrorInesperado(e.toString());
    }
  }
}
