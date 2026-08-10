import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/asignacion_vehiculo_repository.dart';
import '../repositories/vehiculo_kilometraje_repository.dart';
import '../repositories/vehiculo_repository.dart';

sealed class AsignarVehiculoResultado {}

class AsignarVehiculoExitoso extends AsignarVehiculoResultado {
  AsignarVehiculoExitoso(this.asignacion);
  final AsignacionVehiculoData asignacion;
}

class AsignarVehiculoNoExiste extends AsignarVehiculoResultado {}

/// Exactamente uno de empleado/servicio debe venir poblado.
class AsignarVehiculoDestinoInvalido extends AsignarVehiculoResultado {}

/// El Vehículo no está `disponible` (ya asignado, en mantenimiento,
/// fuera de servicio o dado de baja) — no se puede asignar. Incluye el
/// estatus real para que la UI dé un mensaje claro.
class AsignarVehiculoNoDisponible extends AsignarVehiculoResultado {
  AsignarVehiculoNoDisponible(this.estatusActual);
  final String estatusActual;
}

/// El kilometraje de entrega capturado es menor al último conocido —
/// mismo criterio que `RegistrarKilometrajeVehiculoUseCase`: nunca se
/// acepta un decremento silencioso, tampoco aquí.
class AsignarVehiculoKilometrajeMenorAlActual extends AsignarVehiculoResultado {
  AsignarVehiculoKilometrajeMenorAlActual(this.actual);
  final int actual;
}

class AsignarVehiculoErrorInesperado extends AsignarVehiculoResultado {
  AsignarVehiculoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Asigna un Vehículo `disponible` a un Empleado o a un Servicio (Etapa
/// 8B) — el kilometraje de entrega es opcional (punto 10 de Marlon: "no
/// hacer el kilometraje obligatorio si en la operación real no está
/// disponible").
class AsignarVehiculoUseCase {
  AsignarVehiculoUseCase(this._vehiculoRepository, this._asignacionRepository, this._kilometrajeRepository);

  final VehiculoRepository _vehiculoRepository;
  final AsignacionVehiculoRepository _asignacionRepository;
  final VehiculoKilometrajeRepository _kilometrajeRepository;

  Future<AsignarVehiculoResultado> ejecutar({
    required String vehiculoId,
    String? empleadoId,
    String? servicioId,
    required DateTime fechaInicio,
    String? observaciones,
    int? kilometrajeEntrega,
    String? actor,
  }) async {
    if ((empleadoId == null) == (servicioId == null)) return AsignarVehiculoDestinoInvalido();

    final vehiculo = await _vehiculoRepository.obtenerPorId(vehiculoId);
    if (vehiculo == null) return AsignarVehiculoNoExiste();
    if (vehiculo.estatus != 'disponible') return AsignarVehiculoNoDisponible(vehiculo.estatus);

    if (kilometrajeEntrega != null) {
      final actual = await _kilometrajeRepository.obtenerActual(vehiculoId);
      if (actual != null && kilometrajeEntrega < actual.kilometraje) {
        return AsignarVehiculoKilometrajeMenorAlActual(actual.kilometraje);
      }
    }

    try {
      final asignacion = await _asignacionRepository.crear(
        vehiculoId: vehiculoId,
        empleadoId: empleadoId,
        servicioId: servicioId,
        fechaInicio: fechaInicio,
        observaciones: observaciones,
        kilometrajeEntrega: kilometrajeEntrega,
        actor: actor,
      );
      return AsignarVehiculoExitoso(asignacion);
    } catch (e) {
      return AsignarVehiculoErrorInesperado(e.toString());
    }
  }
}
