import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';

import '../repositories/asignacion_servicio_repository.dart';
import '../repositories/empleado_repository.dart';
import 'asignacion_servicio_validator.dart';

sealed class AsignarEmpleadoServicioResultado {}

class AsignarEmpleadoServicioExitoso extends AsignarEmpleadoServicioResultado {
  AsignarEmpleadoServicioExitoso(this.asignacion);
  final AsignacionServicioData asignacion;
}

class AsignarEmpleadoServicioEmpleadoNoExiste extends AsignarEmpleadoServicioResultado {}

class AsignarEmpleadoServicioEmpleadoNoActivo extends AsignarEmpleadoServicioResultado {}

class AsignarEmpleadoServicioYaTieneAsignacionVigente extends AsignarEmpleadoServicioResultado {}

class AsignarEmpleadoServicioServicioNoExiste extends AsignarEmpleadoServicioResultado {}

class AsignarEmpleadoServicioServicioNoActivo extends AsignarEmpleadoServicioResultado {}

class AsignarEmpleadoServicioFechaInvalida extends AsignarEmpleadoServicioResultado {}

class AsignarEmpleadoServicioErrorInesperado extends AsignarEmpleadoServicioResultado {
  AsignarEmpleadoServicioErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Asigna un Empleado activo a un Servicio existente (Etapa 5D) — solo
/// registra Servicio/Turno/Fecha de inicio/Observaciones, nada de
/// horarios/incidencias/PCR (fuera de alcance explícito). Un Empleado
/// solo puede tener una asignación vigente a la vez, reforzado también
/// por el índice único parcial de `AsignacionServicio`.
class AsignarEmpleadoServicioUseCase {
  AsignarEmpleadoServicioUseCase(
    this._empleadoRepository,
    this._asignacionRepository,
    this._servicioRepository,
    this._validator,
  );

  final EmpleadoRepository _empleadoRepository;
  final AsignacionServicioRepository _asignacionRepository;
  final ServicioRepository _servicioRepository;
  final AsignacionServicioValidator _validator;

  Future<AsignarEmpleadoServicioResultado> ejecutar({
    required String empleadoId,
    required String servicioId,
    required DateTime fechaInicio,
    String? turnoId,
    String? observaciones,
    String? actor,
  }) async {
    final empleado = await _empleadoRepository.obtenerPorId(empleadoId);
    if (empleado == null) return AsignarEmpleadoServicioEmpleadoNoExiste();
    if (EstatusEmpleado.values.byName(empleado.estatus) != EstatusEmpleado.activo) {
      return AsignarEmpleadoServicioEmpleadoNoActivo();
    }

    final servicio = await _servicioRepository.obtenerPorId(servicioId);
    if (servicio == null) return AsignarEmpleadoServicioServicioNoExiste();
    if (EstatusServicio.values.byName(servicio.estatus) != EstatusServicio.activo) {
      return AsignarEmpleadoServicioServicioNoActivo();
    }

    final activa = await _asignacionRepository.obtenerActivaPorEmpleado(empleadoId);
    if (activa != null) return AsignarEmpleadoServicioYaTieneAsignacionVigente();

    if (!_validator.fechaInicioValida(fechaInicio, empleado.fechaIngreso)) {
      return AsignarEmpleadoServicioFechaInvalida();
    }

    try {
      final asignacion = await _asignacionRepository.asignar(
        empleadoId: empleadoId,
        servicioId: servicioId,
        fechaInicio: fechaInicio,
        turnoId: turnoId,
        observaciones: observaciones,
        actor: actor,
      );
      return AsignarEmpleadoServicioExitoso(asignacion);
    } catch (e) {
      return AsignarEmpleadoServicioErrorInesperado(e.toString());
    }
  }
}
