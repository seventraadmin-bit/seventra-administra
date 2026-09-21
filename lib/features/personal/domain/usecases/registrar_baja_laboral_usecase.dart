import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';

import 'package:riseg_one/features/inventario/domain/repositories/asignacion_repository.dart';
import 'package:riseg_one/features/vehiculos/domain/repositories/asignacion_vehiculo_repository.dart';

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

/// La persona conserva bienes físicos VIGENTES sin resolver — la baja
/// se rechaza (Ajuste de cierre de la conciliación).
///
/// No es un capricho de la UI: es el dominio el que impide que alguien
/// salga de RISEG dejando un radio en el aire. La única forma de pasar
/// es que cada bien tenga una resolución explícita, que es exactamente
/// lo que `ConciliarBajaEmpleadoUseCase` produce antes de llegar aquí.
class RegistrarBajaLaboralResguardosSinConciliar extends RegistrarBajaLaboralResultado {
  RegistrarBajaLaboralResguardosSinConciliar(this.asignacionIds, this.asignacionVehiculoIds);
  final List<String> asignacionIds;
  final List<String> asignacionVehiculoIds;
}

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
  RegistrarBajaLaboralUseCase(
    this._repository,
    this._validator,
    this._asignacionRepository,
    this._asignacionVehiculoRepository,
  );

  final EmpleadoRepository _repository;
  final EmpleadoValidator _validator;

  /// Para comprobar que no queda ningún bien físico sin resolver. La
  /// verificación es sobre el ESTADO real, no sobre una bandera de
  /// confianza: un bien resuelto o está cerrado (devuelto/perdido/
  /// transferido) o quedó marcado `pendienteRecuperacionDesde` por una
  /// decisión documentada. Lo que no puede quedar es una asignación
  /// vigente y sin marcar, que significaría "nadie dijo qué pasó".
  final AsignacionRepository _asignacionRepository;
  final AsignacionVehiculoRepository _asignacionVehiculoRepository;

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

    // NINGUNA vía puede dar de baja a alguien dejando bienes sin
    // explicar. Antes existía un `marcarBienesPendientes: true` por
    // defecto que marcaba todo como pendiente automáticamente — una
    // puerta trasera al flujo de conciliación, y además un limbo:
    // "pendiente" sin que nadie documentara qué había pasado.
    //
    // Un bien resuelto o está cerrado, o quedó marcado como pendiente
    // por decisión explícita. Una asignación vigente SIN marcar es
    // exactamente "nadie dijo qué pasó con esto".
    final sinResolver = await _asignacionRepository.listarActivasPorEmpleado(empleadoId);
    final vehiculosSinResolver = await _asignacionVehiculoRepository.listarActivasPorEmpleado(empleadoId);
    final inventarioPendiente =
        sinResolver.where((a) => a.pendienteRecuperacionDesde == null).map((a) => a.id).toList();
    final vehiculoPendiente =
        vehiculosSinResolver.where((a) => a.pendienteRecuperacionDesde == null).map((a) => a.id).toList();
    if (inventarioPendiente.isNotEmpty || vehiculoPendiente.isNotEmpty) {
      return RegistrarBajaLaboralResguardosSinConciliar(inventarioPendiente, vehiculoPendiente);
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
