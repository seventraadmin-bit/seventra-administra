import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_comercial_repository.dart';
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

/// Ni la línea comercial elegida (si el Servicio tiene alguna vigente)
/// ni una excepción individual capturada dan un sueldo de referencia —
/// no hay ninguna fuente de la que precargar (toda asignación necesita
/// un sueldo `> 0`).
class AsignarEmpleadoServicioSueldoRequerido extends AsignarEmpleadoServicioResultado {}

class AsignarEmpleadoServicioSueldoInvalido extends AsignarEmpleadoServicioResultado {}

class AsignarEmpleadoServicioBonoInvalido extends AsignarEmpleadoServicioResultado {}

/// El Servicio tiene al menos una línea comercial vigente y no se
/// eligió ninguna (Etapa 15, rediseño de "Condiciones de Personal") —
/// ya no existe la opción de asignar "genérico" perdiendo esa relación.
class AsignarEmpleadoServicioLineaComercialRequerida extends AsignarEmpleadoServicioResultado {}

/// La línea comercial elegida no pertenece a este Servicio, o no tiene
/// una vigencia vigente hoy.
class AsignarEmpleadoServicioLineaComercialInvalida extends AsignarEmpleadoServicioResultado {}

class AsignarEmpleadoServicioErrorInesperado extends AsignarEmpleadoServicioResultado {
  AsignarEmpleadoServicioErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Asigna un Empleado activo a un Servicio existente (Etapa 5D) — solo
/// registra Servicio/Turno/Fecha de inicio/Observaciones, nada de
/// horarios/incidencias/PCR (fuera de alcance explícito). Un Empleado
/// solo puede tener una asignación vigente a la vez, reforzado también
/// por el índice único parcial de `AsignacionServicio`.
///
/// `lineaComercialId` (Etapa 15, rediseño de "Condiciones de Personal")
/// es obligatoria en cuanto el Servicio tiene alguna línea comercial
/// vigente — de ahí se precargan sueldo/bono de referencia (reemplaza
/// el sueldo global de `Servicio`, retirado de la captura nueva).
/// `sueldoMensual`/`bonoMensual` siguen siendo la excepción individual
/// — si se omiten, se precargan desde la vigencia de la línea elegida.
/// El bono, a falta de referencia y de excepción, cae a `0` — nunca
/// bloquea la asignación por sí solo (acepta `0`, a diferencia del
/// sueldo).
class AsignarEmpleadoServicioUseCase {
  AsignarEmpleadoServicioUseCase(
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

  Future<AsignarEmpleadoServicioResultado> ejecutar({
    required String empleadoId,
    required String servicioId,
    required DateTime fechaInicio,
    String? turnoId,
    String? lineaComercialId,
    String? observaciones,
    int? sueldoMensual,
    int? bonoMensual,
    String? actorUsuarioId,
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

    final lineas = await _servicioComercialRepository.listarLineas(servicioId);
    final resolucionLinea = resolverLineaComercialAsignacion(
      lineasDelServicio: lineas,
      lineaComercialId: lineaComercialId,
      sueldoMensual: sueldoMensual,
      bonoMensual: bonoMensual,
    );
    switch (resolucionLinea) {
      case ResolucionLineaComercialRequerida():
        return AsignarEmpleadoServicioLineaComercialRequerida();
      case ResolucionLineaComercialInvalida():
        return AsignarEmpleadoServicioLineaComercialInvalida();
      case ResolucionLineaComercialExitosa():
        break;
    }
    final exitosa = resolucionLinea;

    final sueldoResuelto = exitosa.sueldoResuelto;
    if (sueldoResuelto == null) return AsignarEmpleadoServicioSueldoRequerido();
    if (!_validator.sueldoValido(sueldoResuelto)) return AsignarEmpleadoServicioSueldoInvalido();
    if (!_validator.bonoValido(exitosa.bonoResuelto)) return AsignarEmpleadoServicioBonoInvalido();

    try {
      final asignacion = await _asignacionRepository.asignar(
        empleadoId: empleadoId,
        servicioId: servicioId,
        fechaInicio: fechaInicio,
        sueldoMensual: sueldoResuelto,
        bonoMensual: exitosa.bonoResuelto,
        turnoId: turnoId,
        lineaComercialId: exitosa.linea?.linea.id,
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );
      return AsignarEmpleadoServicioExitoso(asignacion);
    } catch (e) {
      return AsignarEmpleadoServicioErrorInesperado(e.toString());
    }
  }
}
