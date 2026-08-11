import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/complemento_pago_table.dart';

import '../repositories/complemento_pago_repository.dart';

sealed class CancelarComplementoPagoResultado {}

class CancelarComplementoPagoExitoso extends CancelarComplementoPagoResultado {
  CancelarComplementoPagoExitoso(this.complemento);
  final ComplementoPagoData complemento;
}

class CancelarComplementoPagoNoExiste extends CancelarComplementoPagoResultado {}

class CancelarComplementoPagoYaCancelado extends CancelarComplementoPagoResultado {}

class CancelarComplementoPagoErrorInesperado extends CancelarComplementoPagoResultado {
  CancelarComplementoPagoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cancela un Complemento de pago (Etapa 4J.3) — sin cascada (a
/// diferencia de cancelar un `Pago`): un Complemento no tiene
/// entidades hijas que revertir. Cancelarlo reactiva
/// `complementoPendiente`/`cierreCobranzaCompleto` para ese Pago/
/// Cuenta. Requiere `motivo`.
class CancelarComplementoPagoUseCase {
  CancelarComplementoPagoUseCase(this._repository);

  final ComplementoPagoRepository _repository;

  Future<CancelarComplementoPagoResultado> ejecutar({
    required String complementoPagoId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final complemento = await _repository.obtenerPorId(complementoPagoId);
    if (complemento == null) {
      return CancelarComplementoPagoNoExiste();
    }
    if (EstatusComplementoPago.values.byName(complemento.estatus) == EstatusComplementoPago.cancelado) {
      return CancelarComplementoPagoYaCancelado();
    }

    try {
      final actualizado = await _repository.cancelar(complementoPagoId: complementoPagoId, motivo: motivo, actorUsuarioId: actorUsuarioId);
      return CancelarComplementoPagoExitoso(actualizado);
    } catch (e) {
      return CancelarComplementoPagoErrorInesperado(e.toString());
    }
  }
}
