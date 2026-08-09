import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';

import '../repositories/asignacion_servicio_repository.dart';
import '../repositories/empleado_repository.dart';
import 'asignacion_servicio_validator.dart';

sealed class CambiarServicioEmpleadoResultado {}

class CambiarServicioEmpleadoExitoso extends CambiarServicioEmpleadoResultado {
  CambiarServicioEmpleadoExitoso(this.asignacion);
  final AsignacionServicioData asignacion;
}

class CambiarServicioEmpleadoEmpleadoNoExiste extends CambiarServicioEmpleadoResultado {}

class CambiarServicioEmpleadoNoTieneAsignacionVigente extends CambiarServicioEmpleadoResultado {}

class CambiarServicioEmpleadoServicioNoExiste extends CambiarServicioEmpleadoResultado {}

class CambiarServicioEmpleadoServicioNoActivo extends CambiarServicioEmpleadoResultado {}

class CambiarServicioEmpleadoMismoServicio extends CambiarServicioEmpleadoResultado {}

class CambiarServicioEmpleadoFechaInvalida extends CambiarServicioEmpleadoResultado {}

class CambiarServicioEmpleadoErrorInesperado extends CambiarServicioEmpleadoResultado {
  CambiarServicioEmpleadoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Mueve a un Empleado de su Servicio vigente a otro (Etapa 5D) — cierra
/// la asignación anterior (`motivoTermino = cambioServicio`, automático)
/// y crea la nueva, en una sola transacción. Nunca obliga a "retirar
/// primero, asignar después" (Resolución explícita de Marlon).
class CambiarServicioEmpleadoUseCase {
  CambiarServicioEmpleadoUseCase(
    this._empleadoRepository,
    this._asignacionRepository,
    this._servicioRepository,
    this._validator,
  );

  final EmpleadoRepository _empleadoRepository;
  final AsignacionServicioRepository _asignacionRepository;
  final ServicioRepository _servicioRepository;
  final AsignacionServicioValidator _validator;

  Future<CambiarServicioEmpleadoResultado> ejecutar({
    required String empleadoId,
    required String nuevoServicioId,
    required DateTime fecha,
    String? turnoId,
    String? observaciones,
    String? actor,
  }) async {
    final empleado = await _empleadoRepository.obtenerPorId(empleadoId);
    if (empleado == null) return CambiarServicioEmpleadoEmpleadoNoExiste();

    final activa = await _asignacionRepository.obtenerActivaPorEmpleado(empleadoId);
    if (activa == null) return CambiarServicioEmpleadoNoTieneAsignacionVigente();
    if (activa.servicioId == nuevoServicioId) return CambiarServicioEmpleadoMismoServicio();

    final nuevoServicio = await _servicioRepository.obtenerPorId(nuevoServicioId);
    if (nuevoServicio == null) return CambiarServicioEmpleadoServicioNoExiste();
    if (EstatusServicio.values.byName(nuevoServicio.estatus) != EstatusServicio.activo) {
      return CambiarServicioEmpleadoServicioNoActivo();
    }

    if (!_validator.fechaTerminoValida(fecha, activa.fechaInicio)) {
      return CambiarServicioEmpleadoFechaInvalida();
    }

    try {
      final asignacion = await _asignacionRepository.cambiarServicio(
        empleadoId: empleadoId,
        nuevoServicioId: nuevoServicioId,
        fecha: fecha,
        turnoId: turnoId,
        observaciones: observaciones,
        actor: actor,
      );
      return CambiarServicioEmpleadoExitoso(asignacion);
    } catch (e) {
      return CambiarServicioEmpleadoErrorInesperado(e.toString());
    }
  }
}
