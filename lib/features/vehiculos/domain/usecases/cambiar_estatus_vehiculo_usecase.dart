import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/vehiculo_repository.dart';

sealed class CambiarEstatusVehiculoResultado {}

class CambiarEstatusVehiculoExitoso extends CambiarEstatusVehiculoResultado {
  CambiarEstatusVehiculoExitoso(this.vehiculo);
  final VehiculoData vehiculo;
}

class CambiarEstatusVehiculoNoExiste extends CambiarEstatusVehiculoResultado {}

/// El destino no es uno manual válido (`asignado` lo mantiene
/// `AsignacionVehiculo` en la Etapa 8B; `baja` usa
/// `DarDeBajaVehiculoUseCase`).
class CambiarEstatusVehiculoDestinoInvalido extends CambiarEstatusVehiculoResultado {}

class CambiarEstatusVehiculoYaDeBaja extends CambiarEstatusVehiculoResultado {}

class CambiarEstatusVehiculoErrorInesperado extends CambiarEstatusVehiculoResultado {
  CambiarEstatusVehiculoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cambia manualmente el estatus operativo entre `disponible` ⇄
/// `enMantenimiento`/`fueraDeServicio` (Etapa 8A) — nunca hacia
/// `asignado` (transaccional desde `AsignacionVehiculo`, Etapa 8B) ni
/// `baja` (terminal, ver `DarDeBajaVehiculoUseCase`). Un vehículo dado
/// de baja nunca vuelve a cambiar de estatus (sin ciclo de reingreso en
/// este dominio, ver el doc comment de `Vehiculo`).
class CambiarEstatusVehiculoUseCase {
  CambiarEstatusVehiculoUseCase(this._repository);

  final VehiculoRepository _repository;

  static const _destinosValidos = {'disponible', 'enMantenimiento', 'fueraDeServicio'};

  Future<CambiarEstatusVehiculoResultado> ejecutar({required String vehiculoId, required String estatus}) async {
    if (!_destinosValidos.contains(estatus)) return CambiarEstatusVehiculoDestinoInvalido();

    final vehiculo = await _repository.obtenerPorId(vehiculoId);
    if (vehiculo == null) return CambiarEstatusVehiculoNoExiste();
    if (vehiculo.estatus == 'baja') return CambiarEstatusVehiculoYaDeBaja();

    try {
      final actualizado = await _repository.cambiarEstatus(vehiculoId: vehiculoId, estatus: estatus);
      return CambiarEstatusVehiculoExitoso(actualizado);
    } catch (e) {
      return CambiarEstatusVehiculoErrorInesperado(e.toString());
    }
  }
}
