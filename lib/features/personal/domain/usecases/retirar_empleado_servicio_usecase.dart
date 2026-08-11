import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/asignacion_servicio_repository.dart';
import '../repositories/empleado_repository.dart';
import '../../data/tables/asignacion_servicio_table.dart';
import 'asignacion_servicio_validator.dart';

sealed class RetirarEmpleadoServicioResultado {}

class RetirarEmpleadoServicioExitoso extends RetirarEmpleadoServicioResultado {
  RetirarEmpleadoServicioExitoso(this.asignacion);
  final AsignacionServicioData asignacion;
}

class RetirarEmpleadoServicioEmpleadoNoExiste extends RetirarEmpleadoServicioResultado {}

class RetirarEmpleadoServicioNoTieneAsignacionVigente extends RetirarEmpleadoServicioResultado {}

class RetirarEmpleadoServicioMotivoNoSeleccionable extends RetirarEmpleadoServicioResultado {}

class RetirarEmpleadoServicioFechaInvalida extends RetirarEmpleadoServicioResultado {}

class RetirarEmpleadoServicioObservacionesRequeridas extends RetirarEmpleadoServicioResultado {}

class RetirarEmpleadoServicioErrorInesperado extends RetirarEmpleadoServicioResultado {
  RetirarEmpleadoServicioErrorInesperado(this.mensaje);
  final String mensaje;
}

String? _vacioANull(String? valor) {
  final recortado = valor?.trim();
  return (recortado == null || recortado.isEmpty) ? null : recortado;
}

/// Retira a un Empleado de su Servicio vigente sin darlo de baja de la
/// empresa (Etapa 5D) — el Empleado sigue activo, simplemente deja de
/// estar asignado. Solo acepta motivos `seleccionableManualmente`; los
/// 3 motivos automáticos (`cambioServicio`/`bajaEmpleado`/
/// `servicioTerminado`) los coloca el sistema, nunca este caso de uso.
class RetirarEmpleadoServicioUseCase {
  RetirarEmpleadoServicioUseCase(this._empleadoRepository, this._asignacionRepository, this._validator);

  final EmpleadoRepository _empleadoRepository;
  final AsignacionServicioRepository _asignacionRepository;
  final AsignacionServicioValidator _validator;

  Future<RetirarEmpleadoServicioResultado> ejecutar({
    required String empleadoId,
    required DateTime fechaTermino,
    required MotivoTerminoAsignacion motivo,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    final empleado = await _empleadoRepository.obtenerPorId(empleadoId);
    if (empleado == null) return RetirarEmpleadoServicioEmpleadoNoExiste();

    if (!motivo.seleccionableManualmente) return RetirarEmpleadoServicioMotivoNoSeleccionable();

    final activa = await _asignacionRepository.obtenerActivaPorEmpleado(empleadoId);
    if (activa == null) return RetirarEmpleadoServicioNoTieneAsignacionVigente();

    if (!_validator.fechaTerminoValida(fechaTermino, activa.fechaInicio)) {
      return RetirarEmpleadoServicioFechaInvalida();
    }

    final observacionesLimpias = _vacioANull(observaciones);
    if (motivo.requiereObservaciones && observacionesLimpias == null) {
      return RetirarEmpleadoServicioObservacionesRequeridas();
    }

    try {
      final asignacion = await _asignacionRepository.retirar(
        empleadoId: empleadoId,
        fechaTermino: fechaTermino,
        motivo: motivo.name,
        observaciones: observacionesLimpias,
        actorUsuarioId: actorUsuarioId,
      );
      return RetirarEmpleadoServicioExitoso(asignacion);
    } catch (e) {
      return RetirarEmpleadoServicioErrorInesperado(e.toString());
    }
  }
}
