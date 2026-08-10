import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/asignacion_vehiculo_repository.dart';
import '../repositories/vehiculo_repository.dart';

sealed class FinalizarMantenimientoVehiculoResultado {}

class FinalizarMantenimientoVehiculoExitoso extends FinalizarMantenimientoVehiculoResultado {
  FinalizarMantenimientoVehiculoExitoso(this.vehiculo);
  final VehiculoData vehiculo;
}

class FinalizarMantenimientoVehiculoNoExiste extends FinalizarMantenimientoVehiculoResultado {}

class FinalizarMantenimientoVehiculoNoEstaEnMantenimiento extends FinalizarMantenimientoVehiculoResultado {}

class FinalizarMantenimientoVehiculoErrorInesperado extends FinalizarMantenimientoVehiculoResultado {
  FinalizarMantenimientoVehiculoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cierra el paso por `enMantenimiento` y regresa el Vehículo a su
/// estatus operativo correcto (Etapa 8D, punto 3) — nunca un botón
/// crudo "marcar disponible": calcula el destino en vez de asumirlo,
/// exactamente lo que Marlon pidió ("no quiero que los estados queden
/// inconsistentes"). `asignado` si existe una `AsignacionVehiculo`
/// vigente (posible incluso con el Vehículo en mantenimiento — mismo
/// escenario ya documentado en la prueba "no vuelve a disponible si
/// mientras tanto se marcó fuera de servicio", Etapa 8B), `disponible`
/// en caso contrario. `fueraDeServicio` sigue siendo una transición
/// manual explícita (`CambiarEstatusVehiculoUseCase`), no algo que esta
/// clase decida — el operador la usa cuando el mantenimiento revela que
/// el vehículo debe quedar fuera de servicio en vez de regresar a
/// operación.
class FinalizarMantenimientoVehiculoUseCase {
  FinalizarMantenimientoVehiculoUseCase(this._vehiculoRepository, this._asignacionRepository);

  final VehiculoRepository _vehiculoRepository;
  final AsignacionVehiculoRepository _asignacionRepository;

  Future<FinalizarMantenimientoVehiculoResultado> ejecutar({required String vehiculoId}) async {
    final vehiculo = await _vehiculoRepository.obtenerPorId(vehiculoId);
    if (vehiculo == null) return FinalizarMantenimientoVehiculoNoExiste();
    if (vehiculo.estatus != 'enMantenimiento') return FinalizarMantenimientoVehiculoNoEstaEnMantenimiento();

    try {
      final asignacionVigente = await _asignacionRepository.obtenerActivaPorVehiculo(vehiculoId);
      final destino = asignacionVigente != null ? 'asignado' : 'disponible';
      final actualizado = await _vehiculoRepository.cambiarEstatus(vehiculoId: vehiculoId, estatus: destino);
      return FinalizarMantenimientoVehiculoExitoso(actualizado);
    } catch (e) {
      return FinalizarMantenimientoVehiculoErrorInesperado(e.toString());
    }
  }
}
