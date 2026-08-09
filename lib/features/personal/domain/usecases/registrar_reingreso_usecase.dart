import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';

import '../repositories/empleado_repository.dart';
import 'empleado_validator.dart';

sealed class RegistrarReingresoResultado {}

class RegistrarReingresoExitoso extends RegistrarReingresoResultado {
  RegistrarReingresoExitoso(this.empleado);
  final EmpleadoData empleado;
}

class RegistrarReingresoNoExiste extends RegistrarReingresoResultado {}

class RegistrarReingresoNoEstaDeBaja extends RegistrarReingresoResultado {}

class RegistrarReingresoFechaInvalida extends RegistrarReingresoResultado {}

class RegistrarReingresoErrorInesperado extends RegistrarReingresoResultado {
  RegistrarReingresoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Recontrata a un Empleado ya existente (Etapa 5C) — nunca crea un
/// Empleado nuevo, conserva expediente/documentación/evaluaciones/
/// historial administrativo intactos. Archiva el periodo cerrado en
/// `EmpleadoPeriodoLaboral` e inicia uno nuevo desde cero: la
/// antigüedad nunca acumula periodos anteriores (Resolución explícita
/// de Marlon).
class RegistrarReingresoUseCase {
  RegistrarReingresoUseCase(this._repository, this._validator);

  final EmpleadoRepository _repository;
  final EmpleadoValidator _validator;

  Future<RegistrarReingresoResultado> ejecutar({
    required String empleadoId,
    required DateTime fechaIngreso,
    String? puestoId,
    bool limpiarPuesto = false,
    String? sucursalId,
    bool limpiarSucursal = false,
    String? actor,
  }) async {
    final empleado = await _repository.obtenerPorId(empleadoId);
    if (empleado == null) return RegistrarReingresoNoExiste();
    if (EstatusEmpleado.values.byName(empleado.estatus) == EstatusEmpleado.activo) {
      return RegistrarReingresoNoEstaDeBaja();
    }
    if (!_validator.fechaReingresoValida(fechaIngreso, empleado.fechaNacimiento, empleado.fechaBaja)) {
      return RegistrarReingresoFechaInvalida();
    }

    try {
      final actualizado = await _repository.registrarReingreso(
        empleadoId: empleadoId,
        fechaIngreso: fechaIngreso,
        puestoId: puestoId,
        limpiarPuesto: limpiarPuesto,
        sucursalId: sucursalId,
        limpiarSucursal: limpiarSucursal,
        actor: actor,
      );
      return RegistrarReingresoExitoso(actualizado);
    } catch (e) {
      return RegistrarReingresoErrorInesperado(e.toString());
    }
  }
}
