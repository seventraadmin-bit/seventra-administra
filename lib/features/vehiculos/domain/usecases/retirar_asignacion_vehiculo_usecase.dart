import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/asignacion_vehiculo_table.dart' show MotivoTerminoAsignacionVehiculo;
import '../repositories/asignacion_vehiculo_repository.dart';
import '../repositories/vehiculo_kilometraje_repository.dart';

sealed class RetirarAsignacionVehiculoResultado {}

class RetirarAsignacionVehiculoExitoso extends RetirarAsignacionVehiculoResultado {
  RetirarAsignacionVehiculoExitoso(this.asignacion);
  final AsignacionVehiculoData asignacion;
}

class RetirarAsignacionVehiculoNoExiste extends RetirarAsignacionVehiculoResultado {}

class RetirarAsignacionVehiculoYaCerrada extends RetirarAsignacionVehiculoResultado {}

class RetirarAsignacionVehiculoKilometrajeMenorAlActual extends RetirarAsignacionVehiculoResultado {
  RetirarAsignacionVehiculoKilometrajeMenorAlActual(this.actual);
  final int actual;
}

class RetirarAsignacionVehiculoErrorInesperado extends RetirarAsignacionVehiculoResultado {
  RetirarAsignacionVehiculoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Libera un Vehículo (Etapa 8B) — cierra la asignación vigente con
/// motivo `liberacion`; el Vehículo vuelve a `disponible` salvo que ya
/// esté en mantenimiento/fuera de servicio/baja (ver el doc comment de
/// `AsignacionVehiculoRepository.cerrar`). Kilometraje de devolución
/// opcional, mismo criterio que `AsignarVehiculoUseCase`.
class RetirarAsignacionVehiculoUseCase {
  RetirarAsignacionVehiculoUseCase(this._asignacionRepository, this._kilometrajeRepository);

  final AsignacionVehiculoRepository _asignacionRepository;
  final VehiculoKilometrajeRepository _kilometrajeRepository;

  Future<RetirarAsignacionVehiculoResultado> ejecutar({
    required String asignacionVehiculoId,
    required DateTime fechaTermino,
    String? observacionesTermino,
    int? kilometrajeDevolucion,
    String? actor,
  }) async {
    final actual = await _asignacionRepository.obtenerPorId(asignacionVehiculoId);
    if (actual == null) return RetirarAsignacionVehiculoNoExiste();
    if (actual.fechaTermino != null) return RetirarAsignacionVehiculoYaCerrada();

    if (kilometrajeDevolucion != null) {
      final km = await _kilometrajeRepository.obtenerActual(actual.vehiculoId);
      if (km != null && kilometrajeDevolucion < km.kilometraje) {
        return RetirarAsignacionVehiculoKilometrajeMenorAlActual(km.kilometraje);
      }
    }

    try {
      final cerrada = await _asignacionRepository.cerrar(
        asignacionVehiculoId: asignacionVehiculoId,
        fechaTermino: fechaTermino,
        motivoTermino: MotivoTerminoAsignacionVehiculo.liberacion.name,
        observacionesTermino: observacionesTermino,
        kilometrajeDevolucion: kilometrajeDevolucion,
        actor: actor,
      );
      return RetirarAsignacionVehiculoExitoso(cerrada);
    } catch (e) {
      return RetirarAsignacionVehiculoErrorInesperado(e.toString());
    }
  }
}
