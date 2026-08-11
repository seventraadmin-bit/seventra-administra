import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/pago_nomina_repository.dart';

sealed class CancelarPagoNominaResultado {}

class CancelarPagoNominaExitoso extends CancelarPagoNominaResultado {
  CancelarPagoNominaExitoso(this.pagoNomina);
  final PagoNominaData pagoNomina;
}

class CancelarPagoNominaNoExiste extends CancelarPagoNominaResultado {}

class CancelarPagoNominaYaCancelado extends CancelarPagoNominaResultado {}

class CancelarPagoNominaErrorInesperado extends CancelarPagoNominaResultado {
  CancelarPagoNominaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cancela un `PagoNomina` completo (Etapa 6D) — cascada automática de
/// todas sus `AplicacionPagoNomina` vigentes, revierte `estatusPago` de
/// cada renglón afectado, cancela el `Egreso` ligado, y si la Nómina
/// había pasado a `pagada` la regresa a `cerrada` (todo dentro de
/// `PagoNominaRepository.cancelar`) — mismo criterio "nunca bloquea la
/// cancelación por tener aplicaciones activas" que `CancelarPagoUseCase`.
class CancelarPagoNominaUseCase {
  CancelarPagoNominaUseCase(this._repository);

  final PagoNominaRepository _repository;

  Future<CancelarPagoNominaResultado> ejecutar({
    required String pagoNominaId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final pagoNomina = await _repository.obtenerPorId(pagoNominaId);
    if (pagoNomina == null) return CancelarPagoNominaNoExiste();
    if (pagoNomina.estatus == 'cancelado') return CancelarPagoNominaYaCancelado();

    try {
      final actualizado = await _repository.cancelar(pagoNominaId: pagoNominaId, motivo: motivo, actorUsuarioId: actorUsuarioId);
      return CancelarPagoNominaExitoso(actualizado);
    } catch (e) {
      return CancelarPagoNominaErrorInesperado(e.toString());
    }
  }
}
