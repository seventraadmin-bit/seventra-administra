import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';

import '../repositories/pago_repository.dart';

sealed class CancelarPagoResultado {}

class CancelarPagoExitoso extends CancelarPagoResultado {
  CancelarPagoExitoso(this.pago);
  final PagoData pago;
}

class CancelarPagoNoExiste extends CancelarPagoResultado {}

class CancelarPagoYaCancelado extends CancelarPagoResultado {}

class CancelarPagoErrorInesperado extends CancelarPagoResultado {
  CancelarPagoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cancela un Pago completo (Etapa 4J.2, Resolución 7 de Marlon):
/// cancela en cascada automáticamente todas sus aplicaciones vigentes
/// — nunca bloquea la cancelación por tener aplicaciones activas, es
/// la opción más amigable para el usuario. Requiere `motivo`.
class CancelarPagoUseCase {
  CancelarPagoUseCase(this._repository);

  final PagoRepository _repository;

  Future<CancelarPagoResultado> ejecutar({
    required String pagoId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final pago = await _repository.obtenerPorId(pagoId);
    if (pago == null) {
      return CancelarPagoNoExiste();
    }
    if (EstatusPago.values.byName(pago.estatus) == EstatusPago.cancelado) {
      return CancelarPagoYaCancelado();
    }

    try {
      final actualizado = await _repository.cancelar(pagoId: pagoId, motivo: motivo, actorUsuarioId: actorUsuarioId);
      return CancelarPagoExitoso(actualizado);
    } catch (e) {
      return CancelarPagoErrorInesperado(e.toString());
    }
  }
}
