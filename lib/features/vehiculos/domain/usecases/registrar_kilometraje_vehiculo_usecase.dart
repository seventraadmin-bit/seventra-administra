import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/vehiculo_kilometraje_table.dart' show OrigenKilometrajeVehiculo;
import '../repositories/vehiculo_kilometraje_repository.dart';
import '../repositories/vehiculo_repository.dart';

sealed class RegistrarKilometrajeVehiculoResultado {}

class RegistrarKilometrajeVehiculoExitoso extends RegistrarKilometrajeVehiculoResultado {
  RegistrarKilometrajeVehiculoExitoso(this.lectura);
  final VehiculoKilometrajeData lectura;
}

class RegistrarKilometrajeVehiculoNoExiste extends RegistrarKilometrajeVehiculoResultado {}

class RegistrarKilometrajeVehiculoInvalido extends RegistrarKilometrajeVehiculoResultado {}

/// Rechazo por defecto — nunca se acepta un decremento silencioso
/// (instrucción explícita de Marlon). Incluye el valor actual para que
/// la UI ofrezca directamente el flujo de corrección.
class RegistrarKilometrajeVehiculoMenorAlActual extends RegistrarKilometrajeVehiculoResultado {
  RegistrarKilometrajeVehiculoMenorAlActual(this.actual);
  final int actual;
}

/// `origen = correccion` sin observaciones — la trazabilidad de una
/// corrección exige motivo explícito.
class RegistrarKilometrajeVehiculoObservacionesRequeridas extends RegistrarKilometrajeVehiculoResultado {}

class RegistrarKilometrajeVehiculoErrorInesperado extends RegistrarKilometrajeVehiculoResultado {
  RegistrarKilometrajeVehiculoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra una lectura de kilometraje (Etapa 8B, puntos 7-9) — el
/// punto de entrada manual del ledger (`lecturaManual`/`correccion`;
/// `entrega`/`devolucion`/`mantenimiento` los generan otros flujos, ver
/// el doc comment de `OrigenKilometrajeVehiculo`).
///
/// "No permitir registrar un kilometraje menor al último de forma
/// silenciosa. Si existe una corrección, debe ser mediante flujo
/// explícito: valor anterior, valor nuevo, motivo/observación" —
/// mismo criterio exacto que `RegistrarAjusteUseCase` (Inventario)
/// exige `observaciones` para cualquier ajuste manual de existencia.
/// Una corrección puede subir o bajar el valor libremente; cualquier
/// otro origen nunca puede bajarlo.
class RegistrarKilometrajeVehiculoUseCase {
  RegistrarKilometrajeVehiculoUseCase(this._kilometrajeRepository, this._vehiculoRepository);

  final VehiculoKilometrajeRepository _kilometrajeRepository;
  final VehiculoRepository _vehiculoRepository;

  Future<RegistrarKilometrajeVehiculoResultado> ejecutar({
    required String vehiculoId,
    required DateTime fecha,
    required int kilometraje,
    required String origen,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    if (kilometraje < 0) return RegistrarKilometrajeVehiculoInvalido();
    if (await _vehiculoRepository.obtenerPorId(vehiculoId) == null) return RegistrarKilometrajeVehiculoNoExiste();

    final esCorreccion = origen == OrigenKilometrajeVehiculo.correccion.name;
    if (esCorreccion && (observaciones == null || observaciones.trim().isEmpty)) {
      return RegistrarKilometrajeVehiculoObservacionesRequeridas();
    }

    if (!esCorreccion) {
      final actual = await _kilometrajeRepository.obtenerActual(vehiculoId);
      if (actual != null && kilometraje < actual.kilometraje) {
        return RegistrarKilometrajeVehiculoMenorAlActual(actual.kilometraje);
      }
    }

    try {
      final lectura = await _kilometrajeRepository.registrar(
        vehiculoId: vehiculoId,
        fecha: fecha,
        kilometraje: kilometraje,
        origen: origen,
        observaciones: observaciones?.trim().isEmpty ?? true ? null : observaciones!.trim(),
        actorUsuarioId: actorUsuarioId,
      );
      return RegistrarKilometrajeVehiculoExitoso(lectura);
    } catch (e) {
      return RegistrarKilometrajeVehiculoErrorInesperado(e.toString());
    }
  }
}
