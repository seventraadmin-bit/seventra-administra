import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';

import '../repositories/complemento_pago_repository.dart';
import '../repositories/pago_repository.dart';

sealed class CancelarPagoResultado {}

class CancelarPagoExitoso extends CancelarPagoResultado {
  CancelarPagoExitoso(this.pago);
  final PagoData pago;
}

class CancelarPagoNoExiste extends CancelarPagoResultado {}

class CancelarPagoYaCancelado extends CancelarPagoResultado {}

/// Hallazgo real de auditoría (Etapa 6): antes de esta etapa, cancelar
/// un Pago con un `ComplementoPago` real (CFDI ya timbrado ante el
/// SAT) no tenía ningún bloqueo — se cancelaba en cascada como
/// cualquier otro, dejando el Complemento apuntando a un Pago
/// "cancelado" sin ninguna resolución fiscal. Mismo criterio ya
/// establecido por `EliminarPagoFisicamenteUseCase` (bloqueo absoluto,
/// nunca una cascada automática de cancelación fiscal): el usuario
/// debe resolver el Complemento por su propio flujo (mismo criterio
/// que nunca sugerir un "cancelar CFDI" automático) antes de poder
/// cancelar el Pago.
class CancelarPagoComplementoVigente extends CancelarPagoResultado {
  CancelarPagoComplementoVigente(this.uuid);
  final String uuid;
}

class CancelarPagoErrorInesperado extends CancelarPagoResultado {
  CancelarPagoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cancela un Pago completo (Etapa 4J.2, Resolución 7 de Marlon):
/// cancela en cascada automáticamente todas sus aplicaciones vigentes
/// — nunca bloquea la cancelación por tener aplicaciones activas, es
/// la opción más amigable para el usuario — salvo que exista un
/// `ComplementoPago` vigente (Etapa 6, ver
/// [CancelarPagoComplementoVigente]). Requiere `motivo`.
class CancelarPagoUseCase {
  CancelarPagoUseCase(this._repository, this._complementoPagoRepository);

  final PagoRepository _repository;
  final ComplementoPagoRepository _complementoPagoRepository;

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

    // Sólo el Complemento VIGENTE bloquea (schemaVersion 79): uno
    // cancelado ya no documenta nada, y con el modelo de sustitutos un
    // Pago puede arrastrar varios en su histórico. La consulta pide
    // exactamente el vigente, así que no hay que filtrar por estatus
    // aquí.
    final complemento = await _complementoPagoRepository.obtenerVigentePorPagoId(pagoId);
    if (complemento != null) {
      return CancelarPagoComplementoVigente(complemento.uuid);
    }

    try {
      final actualizado = await _repository.cancelar(pagoId: pagoId, motivo: motivo, actorUsuarioId: actorUsuarioId);
      return CancelarPagoExitoso(actualizado);
    } catch (e) {
      return CancelarPagoErrorInesperado(e.toString());
    }
  }
}
