import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/cuenta_por_cobrar_repository.dart';

sealed class QuitarReprogramacionCobroCuentaPorCobrarResultado {}

class QuitarReprogramacionCobroCuentaPorCobrarExitoso extends QuitarReprogramacionCobroCuentaPorCobrarResultado {
  QuitarReprogramacionCobroCuentaPorCobrarExitoso(this.cuenta);
  final CuentaPorCobrarData cuenta;
}

class QuitarReprogramacionCobroCuentaPorCobrarNoExiste extends QuitarReprogramacionCobroCuentaPorCobrarResultado {}

/// No tenía ninguna reprogramación capturada — nada que quitar. No es
/// un error, pero tampoco produce ningún evento nuevo (evita un
/// `CuentaPorCobrarEvento` vacío/redundante).
class QuitarReprogramacionCobroCuentaPorCobrarSinReprogramacion
    extends QuitarReprogramacionCobroCuentaPorCobrarResultado {}

class QuitarReprogramacionCobroCuentaPorCobrarMotivoRequerido
    extends QuitarReprogramacionCobroCuentaPorCobrarResultado {}

class QuitarReprogramacionCobroCuentaPorCobrarErrorInesperado
    extends QuitarReprogramacionCobroCuentaPorCobrarResultado {
  QuitarReprogramacionCobroCuentaPorCobrarErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Quita una reprogramación de cobro capturada por error (Etapa 7,
/// Sección 5 del pedido) — semántica propia y bien tipada sobre el
/// mismo mecanismo ya existente en
/// `CuentaPorCobrarRepository.reprogramarCobro(fechaCobroReprogramada:
/// null)` (nunca una operación nueva a nivel de repositorio: el
/// "limpiar" ya estaba soportado ahí, solo le faltaba una vía de UI y
/// un caso de uso propio con su resultado tipado). Tras quitarla, la
/// Planeación vuelve a usar `fechaVencimiento` (la fecha contractual)
/// para proyectar el cobro, si la cuenta sigue vencida.
class QuitarReprogramacionCobroCuentaPorCobrarUseCase {
  QuitarReprogramacionCobroCuentaPorCobrarUseCase(this._repository);

  final CuentaPorCobrarRepository _repository;

  Future<QuitarReprogramacionCobroCuentaPorCobrarResultado> ejecutar({
    required String cuentaPorCobrarId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) return QuitarReprogramacionCobroCuentaPorCobrarMotivoRequerido();

    final cuenta = await _repository.obtenerPorId(cuentaPorCobrarId);
    if (cuenta == null) {
      return QuitarReprogramacionCobroCuentaPorCobrarNoExiste();
    }
    if (cuenta.fechaCobroReprogramada == null) {
      return QuitarReprogramacionCobroCuentaPorCobrarSinReprogramacion();
    }

    try {
      final actualizada = await _repository.reprogramarCobro(
        cuentaPorCobrarId: cuentaPorCobrarId,
        fechaCobroReprogramada: null,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return QuitarReprogramacionCobroCuentaPorCobrarExitoso(actualizada);
    } catch (e) {
      return QuitarReprogramacionCobroCuentaPorCobrarErrorInesperado(e.toString());
    }
  }
}
