import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/linea_telefonica_plan_repository.dart';
import '../repositories/linea_telefonica_repository.dart';

sealed class RegistrarPlanLineaTelefonicaResultado {}

class RegistrarPlanLineaTelefonicaExitoso extends RegistrarPlanLineaTelefonicaResultado {
  RegistrarPlanLineaTelefonicaExitoso(this.plan);
  final LineaTelefonicaPlanData plan;
}

class RegistrarPlanLineaTelefonicaLineaNoExiste extends RegistrarPlanLineaTelefonicaResultado {}

/// La línea ya está de baja — no tiene sentido registrar un plan nuevo
/// para una línea terminal.
class RegistrarPlanLineaTelefonicaLineaDeBaja extends RegistrarPlanLineaTelefonicaResultado {}

class RegistrarPlanLineaTelefonicaNombreRequerido extends RegistrarPlanLineaTelefonicaResultado {}

class RegistrarPlanLineaTelefonicaCostoInvalido extends RegistrarPlanLineaTelefonicaResultado {}

class RegistrarPlanLineaTelefonicaPermanenciaInvalida extends RegistrarPlanLineaTelefonicaResultado {}

class RegistrarPlanLineaTelefonicaErrorInesperado extends RegistrarPlanLineaTelefonicaResultado {
  RegistrarPlanLineaTelefonicaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra el plan/costo de una línea telefónica (Etapa 9A) — sirve
/// tanto para el primer plan de una línea como para "cambiar plan": es
/// el mismo caso de uso, `LineaTelefonicaPlanRepository.cambiarPlan`
/// cierra el vigente (si existe) e inserta el nuevo en una transacción
/// (ver el doc comment de `LineaTelefonicaPlan`).
class RegistrarPlanLineaTelefonicaUseCase {
  RegistrarPlanLineaTelefonicaUseCase(this._planRepository, this._lineaRepository);

  final LineaTelefonicaPlanRepository _planRepository;
  final LineaTelefonicaRepository _lineaRepository;

  Future<RegistrarPlanLineaTelefonicaResultado> ejecutar({
    required String lineaTelefonicaId,
    required String nombre,
    required int costoMensual,
    required DateTime fechaInicioVigencia,
    DateTime? fechaFinPermanencia,
    String? observaciones,
  }) async {
    final linea = await _lineaRepository.obtenerPorId(lineaTelefonicaId);
    if (linea == null) return RegistrarPlanLineaTelefonicaLineaNoExiste();
    if (linea.estatus == 'baja') return RegistrarPlanLineaTelefonicaLineaDeBaja();
    if (nombre.trim().isEmpty) return RegistrarPlanLineaTelefonicaNombreRequerido();
    if (costoMensual < 0) return RegistrarPlanLineaTelefonicaCostoInvalido();
    if (fechaFinPermanencia != null && fechaFinPermanencia.isBefore(fechaInicioVigencia)) {
      return RegistrarPlanLineaTelefonicaPermanenciaInvalida();
    }

    try {
      final plan = await _planRepository.cambiarPlan(
        lineaTelefonicaId: lineaTelefonicaId,
        nombre: nombre.trim(),
        costoMensual: costoMensual,
        fechaInicioVigencia: fechaInicioVigencia,
        fechaFinPermanencia: fechaFinPermanencia,
        observaciones: observaciones?.trim().isEmpty ?? true ? null : observaciones!.trim(),
      );
      return RegistrarPlanLineaTelefonicaExitoso(plan);
    } catch (e) {
      return RegistrarPlanLineaTelefonicaErrorInesperado(e.toString());
    }
  }
}
