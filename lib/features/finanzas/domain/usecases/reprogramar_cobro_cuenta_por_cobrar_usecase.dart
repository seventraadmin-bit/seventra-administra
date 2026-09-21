import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart';

import '../repositories/cuenta_por_cobrar_repository.dart';

sealed class ReprogramarCobroCuentaPorCobrarResultado {}

class ReprogramarCobroCuentaPorCobrarExitoso extends ReprogramarCobroCuentaPorCobrarResultado {
  ReprogramarCobroCuentaPorCobrarExitoso(this.cuenta);
  final CuentaPorCobrarData cuenta;
}

class ReprogramarCobroCuentaPorCobrarNoExiste extends ReprogramarCobroCuentaPorCobrarResultado {}

class ReprogramarCobroCuentaPorCobrarCancelada extends ReprogramarCobroCuentaPorCobrarResultado {}

class ReprogramarCobroCuentaPorCobrarMotivoRequerido extends ReprogramarCobroCuentaPorCobrarResultado {}

class ReprogramarCobroCuentaPorCobrarErrorInesperado extends ReprogramarCobroCuentaPorCobrarResultado {
  ReprogramarCobroCuentaPorCobrarErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Reprograma la expectativa de cobro de una Cuenta por cobrar ya
/// vencida (Etapa 19D, "Calendario financiero y planeación de
/// liquidez") — **distinto** de `CorregirCuentaPorCobrarUseCase`: ese
/// sobrescribe `fechaVencimiento` (la fecha contractual); este captura
/// `fechaCobroReprogramada` sin tocarla, para que la fecha original
/// siga siendo consultable. `fechaCobroReprogramada: null` limpia la
/// reprogramación — ver `QuitarReprogramacionCobroCuentaPorCobrarUseCase`,
/// que reutiliza este mismo caso de uso con una semántica propia.
class ReprogramarCobroCuentaPorCobrarUseCase {
  ReprogramarCobroCuentaPorCobrarUseCase(this._repository);

  final CuentaPorCobrarRepository _repository;

  Future<ReprogramarCobroCuentaPorCobrarResultado> ejecutar({
    required String cuentaPorCobrarId,
    required DateTime? fechaCobroReprogramada,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) return ReprogramarCobroCuentaPorCobrarMotivoRequerido();

    final cuenta = await _repository.obtenerPorId(cuentaPorCobrarId);
    if (cuenta == null) {
      return ReprogramarCobroCuentaPorCobrarNoExiste();
    }
    if (EstatusCuentaPorCobrar.values.byName(cuenta.estatus) == EstatusCuentaPorCobrar.cancelada) {
      return ReprogramarCobroCuentaPorCobrarCancelada();
    }

    try {
      final actualizada = await _repository.reprogramarCobro(
        cuentaPorCobrarId: cuentaPorCobrarId,
        fechaCobroReprogramada: fechaCobroReprogramada,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return ReprogramarCobroCuentaPorCobrarExitoso(actualizada);
    } catch (e) {
      return ReprogramarCobroCuentaPorCobrarErrorInesperado(e.toString());
    }
  }
}
