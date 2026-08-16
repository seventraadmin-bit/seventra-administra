import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_comercial_repository.dart';
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

/// Mismo criterio que `AsignarEmpleadoServicioSueldoRequerido`: ni la
/// línea comercial elegida del nuevo Servicio ni una excepción
/// individual capturada dan un sueldo de referencia.
class CambiarServicioEmpleadoSueldoRequerido extends CambiarServicioEmpleadoResultado {}

class CambiarServicioEmpleadoSueldoInvalido extends CambiarServicioEmpleadoResultado {}

class CambiarServicioEmpleadoBonoInvalido extends CambiarServicioEmpleadoResultado {}

/// El nuevo Servicio tiene al menos una línea comercial vigente y no se
/// eligió ninguna (Etapa 15, rediseño de "Condiciones de Personal").
class CambiarServicioEmpleadoLineaComercialRequerida extends CambiarServicioEmpleadoResultado {}

/// La línea comercial elegida no pertenece al nuevo Servicio, o no
/// tiene una vigencia vigente hoy.
class CambiarServicioEmpleadoLineaComercialInvalida extends CambiarServicioEmpleadoResultado {}

class CambiarServicioEmpleadoErrorInesperado extends CambiarServicioEmpleadoResultado {
  CambiarServicioEmpleadoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Mueve a un Empleado de su Servicio vigente a otro (Etapa 5D) — cierra
/// la asignación anterior (`motivoTermino = cambioServicio`, automático)
/// y crea la nueva, en una sola transacción. Nunca obliga a "retirar
/// primero, asignar después" (Resolución explícita de Marlon).
///
/// `sueldoMensual`/`bonoMensual` son la excepción individual de la
/// asignación *nueva* — mismo criterio de precarga/resolución que
/// `AsignarEmpleadoServicioUseCase` (Etapa 15: desde la línea comercial
/// elegida del nuevo Servicio, ya no desde su sueldo global). La
/// asignación anterior conserva su propio historial de vigencias de
/// sueldo sin tocarse.
class CambiarServicioEmpleadoUseCase {
  CambiarServicioEmpleadoUseCase(
    this._empleadoRepository,
    this._asignacionRepository,
    this._servicioRepository,
    this._servicioComercialRepository,
    this._validator,
  );

  final EmpleadoRepository _empleadoRepository;
  final AsignacionServicioRepository _asignacionRepository;
  final ServicioRepository _servicioRepository;
  final ServicioComercialRepository _servicioComercialRepository;
  final AsignacionServicioValidator _validator;

  Future<CambiarServicioEmpleadoResultado> ejecutar({
    required String empleadoId,
    required String nuevoServicioId,
    required DateTime fecha,
    String? turnoId,
    String? lineaComercialId,
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

    final lineas = await _servicioComercialRepository.listarLineas(nuevoServicioId);
    final resolucionLinea = resolverLineaComercialAsignacion(
      lineasDelServicio: lineas,
      lineaComercialId: lineaComercialId,
      sueldoMensual: sueldoMensual,
      bonoMensual: bonoMensual,
    );
    switch (resolucionLinea) {
      case ResolucionLineaComercialRequerida():
        return CambiarServicioEmpleadoLineaComercialRequerida();
      case ResolucionLineaComercialInvalida():
        return CambiarServicioEmpleadoLineaComercialInvalida();
      case ResolucionLineaComercialExitosa():
        break;
    }
    final exitosa = resolucionLinea;

    final sueldoResuelto = exitosa.sueldoResuelto;
    if (sueldoResuelto == null) return CambiarServicioEmpleadoSueldoRequerido();
    if (!_validator.sueldoValido(sueldoResuelto)) return CambiarServicioEmpleadoSueldoInvalido();
    if (!_validator.bonoValido(exitosa.bonoResuelto)) return CambiarServicioEmpleadoBonoInvalido();

    try {
      final asignacion = await _asignacionRepository.cambiarServicio(
        empleadoId: empleadoId,
        nuevoServicioId: nuevoServicioId,
        fecha: fecha,
        sueldoMensual: sueldoResuelto,
        bonoMensual: exitosa.bonoResuelto,
        turnoId: turnoId,
        lineaComercialId: exitosa.linea?.linea.id,
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );
      return CambiarServicioEmpleadoExitoso(asignacion);
    } catch (e) {
      return CambiarServicioEmpleadoErrorInesperado(e.toString());
    }
  }
}
