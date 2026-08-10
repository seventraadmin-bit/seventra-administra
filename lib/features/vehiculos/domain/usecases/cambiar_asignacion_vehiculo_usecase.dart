import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/asignacion_vehiculo_repository.dart';

sealed class CambiarAsignacionVehiculoResultado {}

class CambiarAsignacionVehiculoExitoso extends CambiarAsignacionVehiculoResultado {
  CambiarAsignacionVehiculoExitoso(this.nuevaAsignacion);
  final AsignacionVehiculoData nuevaAsignacion;
}

class CambiarAsignacionVehiculoNoExiste extends CambiarAsignacionVehiculoResultado {}

class CambiarAsignacionVehiculoYaCerrada extends CambiarAsignacionVehiculoResultado {}

/// Exactamente uno del nuevo empleado/servicio debe venir poblado.
class CambiarAsignacionVehiculoDestinoInvalido extends CambiarAsignacionVehiculoResultado {}

class CambiarAsignacionVehiculoErrorInesperado extends CambiarAsignacionVehiculoResultado {
  CambiarAsignacionVehiculoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// "Cambiar asignación" (Etapa 8B, punto 3) — cierra la vigente
/// (motivo `cambioResponsable`, automático) y crea la nueva, una sola
/// operación. El Vehículo se queda `asignado` durante todo el proceso
/// (nunca pasa visiblemente por `disponible`). Sin captura de
/// kilometraje aquí — a diferencia de asignar/retirar, un cambio de
/// responsable no representa un movimiento físico distinto del
/// vehículo en el mismo instante (punto 10 solo menciona entrega y
/// devolución, deliberadamente no cambio de responsable).
class CambiarAsignacionVehiculoUseCase {
  CambiarAsignacionVehiculoUseCase(this._asignacionRepository);

  final AsignacionVehiculoRepository _asignacionRepository;

  Future<CambiarAsignacionVehiculoResultado> ejecutar({
    required String asignacionVehiculoActualId,
    required DateTime fecha,
    String? observacionesTermino,
    String? nuevoEmpleadoId,
    String? nuevoServicioId,
    String? observacionesNueva,
    String? actor,
  }) async {
    if ((nuevoEmpleadoId == null) == (nuevoServicioId == null)) {
      return CambiarAsignacionVehiculoDestinoInvalido();
    }

    final actual = await _asignacionRepository.obtenerPorId(asignacionVehiculoActualId);
    if (actual == null) return CambiarAsignacionVehiculoNoExiste();
    if (actual.fechaTermino != null) return CambiarAsignacionVehiculoYaCerrada();

    try {
      final nueva = await _asignacionRepository.cambiarResponsable(
        asignacionVehiculoActualId: asignacionVehiculoActualId,
        fecha: fecha,
        observacionesTermino: observacionesTermino,
        nuevoEmpleadoId: nuevoEmpleadoId,
        nuevoServicioId: nuevoServicioId,
        observacionesNueva: observacionesNueva,
        actor: actor,
      );
      return CambiarAsignacionVehiculoExitoso(nueva);
    } catch (e) {
      return CambiarAsignacionVehiculoErrorInesperado(e.toString());
    }
  }
}
