import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';

import '../repositories/empleado_repository.dart';

sealed class CambiarEstatusEmpleadoResultado {}

class CambiarEstatusEmpleadoExitoso extends CambiarEstatusEmpleadoResultado {
  CambiarEstatusEmpleadoExitoso(this.empleado);
  final EmpleadoData empleado;
}

class CambiarEstatusEmpleadoNoExiste extends CambiarEstatusEmpleadoResultado {}

class CambiarEstatusEmpleadoYaEnEseEstatus extends CambiarEstatusEmpleadoResultado {}

class CambiarEstatusEmpleadoErrorInesperado extends CambiarEstatusEmpleadoResultado {
  CambiarEstatusEmpleadoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cambia el estatus de un Empleado (`activo`/`baja`) — acción
/// administrativa explícita, separada de `CorregirEmpleadoUseCase`
/// (mismo criterio que `CambiarEstatusServicioUseCase`).
class CambiarEstatusEmpleadoUseCase {
  CambiarEstatusEmpleadoUseCase(this._repository);

  final EmpleadoRepository _repository;

  Future<CambiarEstatusEmpleadoResultado> ejecutar({
    required String empleadoId,
    required EstatusEmpleado nuevo,
    String? motivo,
    String? actor,
  }) async {
    final actual = await _repository.obtenerPorId(empleadoId);
    if (actual == null) return CambiarEstatusEmpleadoNoExiste();
    if (EstatusEmpleado.values.byName(actual.estatus) == nuevo) {
      return CambiarEstatusEmpleadoYaEnEseEstatus();
    }

    try {
      final actualizado = await _repository.cambiarEstatus(
        empleadoId: empleadoId,
        nuevo: nuevo.name,
        motivo: motivo,
        actor: actor,
      );
      return CambiarEstatusEmpleadoExitoso(actualizado);
    } catch (e) {
      return CambiarEstatusEmpleadoErrorInesperado(e.toString());
    }
  }
}
