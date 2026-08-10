import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/vehiculo_table.dart' show MotivoBajaVehiculo;
import '../repositories/vehiculo_repository.dart';

sealed class DarDeBajaVehiculoResultado {}

class DarDeBajaVehiculoExitoso extends DarDeBajaVehiculoResultado {
  DarDeBajaVehiculoExitoso(this.vehiculo);
  final VehiculoData vehiculo;
}

class DarDeBajaVehiculoNoExiste extends DarDeBajaVehiculoResultado {}

class DarDeBajaVehiculoYaDeBaja extends DarDeBajaVehiculoResultado {}

class DarDeBajaVehiculoObservacionesRequeridas extends DarDeBajaVehiculoResultado {}

class DarDeBajaVehiculoErrorInesperado extends DarDeBajaVehiculoResultado {
  DarDeBajaVehiculoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Baja terminal de un Vehículo (Etapa 8A) — `robo`/`perdidaTotal`/
/// `otro` exigen `observacionesBaja` (propiedad del enum, ver el doc
/// comment de `MotivoBajaVehiculo`). Nunca borra el expediente: el
/// Vehículo sigue siendo consultable, solo cambia de estatus.
///
/// Desde la Etapa 8B, este caso de uso también cerrará la
/// `AsignacionVehiculo` vigente en la misma transacción (motivo
/// automático `bajaVehiculo`) — en 8A no existe esa tabla todavía, así
/// que no hay nada que cerrar.
class DarDeBajaVehiculoUseCase {
  DarDeBajaVehiculoUseCase(this._repository);

  final VehiculoRepository _repository;

  Future<DarDeBajaVehiculoResultado> ejecutar({
    required String vehiculoId,
    required DateTime fechaBaja,
    required MotivoBajaVehiculo motivoBaja,
    String? observacionesBaja,
  }) async {
    final vehiculo = await _repository.obtenerPorId(vehiculoId);
    if (vehiculo == null) return DarDeBajaVehiculoNoExiste();
    if (vehiculo.estatus == 'baja') return DarDeBajaVehiculoYaDeBaja();
    if (motivoBaja.requiereObservaciones && (observacionesBaja == null || observacionesBaja.trim().isEmpty)) {
      return DarDeBajaVehiculoObservacionesRequeridas();
    }

    try {
      final actualizado = await _repository.darDeBaja(
        vehiculoId: vehiculoId,
        fechaBaja: fechaBaja,
        motivoBaja: motivoBaja.name,
        observacionesBaja: observacionesBaja?.trim().isEmpty ?? true ? null : observacionesBaja!.trim(),
      );
      return DarDeBajaVehiculoExitoso(actualizado);
    } catch (e) {
      return DarDeBajaVehiculoErrorInesperado(e.toString());
    }
  }
}
