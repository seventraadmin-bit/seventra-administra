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

/// Mismo criterio que `AsignarEmpleadoServicioSueldoRequerido`: el nuevo
/// Servicio no tiene sueldo de referencia y tampoco se capturó una
/// excepción individual.
class CambiarServicioEmpleadoSueldoRequerido extends CambiarServicioEmpleadoResultado {}

class CambiarServicioEmpleadoSueldoInvalido extends CambiarServicioEmpleadoResultado {}

class CambiarServicioEmpleadoBonoInvalido extends CambiarServicioEmpleadoResultado {}

class CambiarServicioEmpleadoErrorInesperado extends CambiarServicioEmpleadoResultado {
  CambiarServicioEmpleadoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Mueve a un Empleado de su Servicio vigente a otro (Etapa 5D) — cierra
/// la asignación anterior (`motivoTermino = cambioServicio`, automático)
/// y crea la nueva, en una sola transacción. Nunca obliga a "retirar
/// primero, asignar después" (Resolución explícita de Marlon).
///
/// `sueldoMensual`/`bonoMensual` (Etapa 6B) son la excepción individual
/// de la asignación *nueva* — mismo criterio de precarga/resolución que
/// `AsignarEmpleadoServicioUseCase`. La asignación anterior conserva su
/// propio historial de vigencias de sueldo sin tocarse.
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
    int? sueldoMensual,
    int? bonoMensual,
    String? actorUsuarioId,
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

    final sueldoResuelto = sueldoMensual ?? nuevoServicio.sueldoMensualReferenciaPersonal;
    if (sueldoResuelto == null) return CambiarServicioEmpleadoSueldoRequerido();
    if (!_validator.sueldoValido(sueldoResuelto)) return CambiarServicioEmpleadoSueldoInvalido();

    final bonoResuelto = bonoMensual ?? nuevoServicio.bonoMensualReferenciaPersonal ?? 0;
    if (!_validator.bonoValido(bonoResuelto)) return CambiarServicioEmpleadoBonoInvalido();

    try {
      final asignacion = await _asignacionRepository.cambiarServicio(
        empleadoId: empleadoId,
        nuevoServicioId: nuevoServicioId,
        fecha: fecha,
        sueldoMensual: sueldoResuelto,
        bonoMensual: bonoResuelto,
        turnoId: turnoId,
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );
      return CambiarServicioEmpleadoExitoso(asignacion);
    } catch (e) {
      return CambiarServicioEmpleadoErrorInesperado(e.toString());
    }
  }
}
