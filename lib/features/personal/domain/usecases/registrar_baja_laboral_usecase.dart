import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';

import '../repositories/empleado_repository.dart';
import 'empleado_validator.dart';

sealed class RegistrarBajaLaboralResultado {}

class RegistrarBajaLaboralExitoso extends RegistrarBajaLaboralResultado {
  RegistrarBajaLaboralExitoso(this.empleado);
  final EmpleadoData empleado;
}

class RegistrarBajaLaboralNoExiste extends RegistrarBajaLaboralResultado {}

class RegistrarBajaLaboralYaDeBaja extends RegistrarBajaLaboralResultado {}

class RegistrarBajaLaboralFechaInvalida extends RegistrarBajaLaboralResultado {}

class RegistrarBajaLaboralObservacionesRequeridas extends RegistrarBajaLaboralResultado {}

class RegistrarBajaLaboralErrorInesperado extends RegistrarBajaLaboralResultado {
  RegistrarBajaLaboralErrorInesperado(this.mensaje);
  final String mensaje;
}

String? _vacioANull(String? valor) {
  final recortado = valor?.trim();
  return (recortado == null || recortado.isEmpty) ? null : recortado;
}

/// Cierra el periodo laboral vigente de un Empleado (Etapa 5C) — nunca
/// borra al Empleado, solo cambia `estatus` a `baja` y completa
/// `fechaBaja`/`motivoBaja`/`observacionesBaja` del periodo vigente.
/// `EmpleadoPeriodoLaboral` no se toca aquí (ese periodo cerrado se
/// archiva únicamente cuando haya un Reingreso posterior — ver
/// `RegistrarReingresoUseCase`).
class RegistrarBajaLaboralUseCase {
  RegistrarBajaLaboralUseCase(this._repository, this._validator);

  final EmpleadoRepository _repository;
  final EmpleadoValidator _validator;

  Future<RegistrarBajaLaboralResultado> ejecutar({
    required String empleadoId,
    required DateTime fechaBaja,
    required MotivoBajaEmpleado motivo,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    final empleado = await _repository.obtenerPorId(empleadoId);
    if (empleado == null) return RegistrarBajaLaboralNoExiste();
    if (EstatusEmpleado.values.byName(empleado.estatus) == EstatusEmpleado.baja) {
      return RegistrarBajaLaboralYaDeBaja();
    }
    if (!_validator.fechaBajaValida(fechaBaja, empleado.fechaIngreso)) return RegistrarBajaLaboralFechaInvalida();
    final observacionesLimpias = _vacioANull(observaciones);
    if (motivo.requiereObservaciones && observacionesLimpias == null) {
      return RegistrarBajaLaboralObservacionesRequeridas();
    }

    try {
      final actualizado = await _repository.registrarBajaLaboral(
        empleadoId: empleadoId,
        fechaBaja: fechaBaja,
        motivo: motivo.name,
        observaciones: observacionesLimpias,
        actorUsuarioId: actorUsuarioId,
      );
      return RegistrarBajaLaboralExitoso(actualizado);
    } catch (e) {
      return RegistrarBajaLaboralErrorInesperado(e.toString());
    }
  }
}
