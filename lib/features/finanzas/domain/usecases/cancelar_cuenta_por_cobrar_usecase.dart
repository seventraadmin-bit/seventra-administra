import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';

import '../repositories/cuenta_por_cobrar_repository.dart';
import '../repositories/pago_repository.dart';

sealed class CancelarCuentaPorCobrarResultado {}

class CancelarCuentaPorCobrarExitoso extends CancelarCuentaPorCobrarResultado {
  CancelarCuentaPorCobrarExitoso(this.cuenta);
  final CuentaPorCobrarData cuenta;
}

class CancelarCuentaPorCobrarNoExiste extends CancelarCuentaPorCobrarResultado {}

class CancelarCuentaPorCobrarYaCancelada extends CancelarCuentaPorCobrarResultado {}

/// Sección 6 del pedido (regla preferida de Marlon, confirmada): una
/// CxC con al menos una `AplicacionPago` vigente (`estatus ==
/// aplicada`) nunca se cancela directamente — el usuario debe primero
/// corregir/cancelar/reaplicar el Pago correspondiente (flujo de Pagos
/// de la Etapa 6). Nunca se cancelan Pagos/aplicaciones en cascada
/// desde aquí. Cubre también el caso `pagada` sin necesidad de un
/// chequeo aparte: una CxC `pagada` siempre tiene al menos una
/// aplicación vigente por definición (`saldoPendiente` solo llega a 0
/// vía `PagoRepository.aplicar`).
class CancelarCuentaPorCobrarTieneAplicacionesActivas extends CancelarCuentaPorCobrarResultado {
  CancelarCuentaPorCobrarTieneAplicacionesActivas(this.cantidad);
  final int cantidad;
}

class CancelarCuentaPorCobrarMotivoRequerido extends CancelarCuentaPorCobrarResultado {}

class CancelarCuentaPorCobrarErrorInesperado extends CancelarCuentaPorCobrarResultado {
  CancelarCuentaPorCobrarErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cancela la obligación de cobro completa (Etapa 7) — distinta de
/// eliminarla físicamente (que esta etapa deliberadamente NO
/// implementa como operación independiente: una CxC vive en relación
/// 1:1 estricta con su `DocumentoPorEmitir`, borrarla sola dejaría un
/// Documento `procesadoAceptado` sin su Cuenta por cobrar). Conserva el
/// registro completo — nunca borra nada, solo `estatus = cancelada` +
/// `saldoPendiente = 0`.
///
/// Nunca toca `DocumentoPorEmitir` (confirmado con Marlon: la
/// dependencia Documento→CxC es de una sola vía; si también se quiere
/// cancelar el Documento, se hace por su propio flujo, ya existente e
/// independiente — `DocumentoPorEmitir` tiene su propio estatus
/// `cancelado`).
class CancelarCuentaPorCobrarUseCase {
  CancelarCuentaPorCobrarUseCase(this._repository, this._pagoRepository);

  final CuentaPorCobrarRepository _repository;
  final PagoRepository _pagoRepository;

  Future<CancelarCuentaPorCobrarResultado> ejecutar({
    required String cuentaPorCobrarId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) return CancelarCuentaPorCobrarMotivoRequerido();

    final cuenta = await _repository.obtenerPorId(cuentaPorCobrarId);
    if (cuenta == null) return CancelarCuentaPorCobrarNoExiste();
    if (EstatusCuentaPorCobrar.values.byName(cuenta.estatus) == EstatusCuentaPorCobrar.cancelada) {
      return CancelarCuentaPorCobrarYaCancelada();
    }

    final aplicaciones = await _pagoRepository.listarAplicacionesPorCuenta(cuentaPorCobrarId);
    final activas = aplicaciones.where((a) => EstatusAplicacionPago.values.byName(a.estatus) == EstatusAplicacionPago.aplicada);
    if (activas.isNotEmpty) {
      return CancelarCuentaPorCobrarTieneAplicacionesActivas(activas.length);
    }

    try {
      final actualizada = await _repository.cancelar(
        cuentaPorCobrarId: cuentaPorCobrarId,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return CancelarCuentaPorCobrarExitoso(actualizada);
    } catch (e) {
      return CancelarCuentaPorCobrarErrorInesperado(e.toString());
    }
  }
}
