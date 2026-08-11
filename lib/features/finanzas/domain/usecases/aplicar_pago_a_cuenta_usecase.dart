import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';

import '../repositories/cuenta_por_cobrar_repository.dart';
import '../repositories/pago_repository.dart';

sealed class AplicarPagoACuentaResultado {}

class AplicarPagoACuentaExitoso extends AplicarPagoACuentaResultado {
  AplicarPagoACuentaExitoso(this.aplicacion);
  final AplicacionPagoData aplicacion;
}

class AplicarPagoACuentaPagoNoExiste extends AplicarPagoACuentaResultado {}

class AplicarPagoACuentaPagoCancelado extends AplicarPagoACuentaResultado {}

class AplicarPagoACuentaCuentaNoExiste extends AplicarPagoACuentaResultado {}

/// La Cuenta por cobrar pertenece a un Cliente distinto al del Pago —
/// un Pago solo puede aplicarse a Cuentas del mismo Cliente.
class AplicarPagoACuentaClienteNoCoincide extends AplicarPagoACuentaResultado {}

class AplicarPagoACuentaCuentaYaPagada extends AplicarPagoACuentaResultado {}

class AplicarPagoACuentaMontoInvalido extends AplicarPagoACuentaResultado {}

/// `monto` excede lo que el Pago todavía tiene sin aplicar
/// (`montoTotal - montoAplicado`) — nunca se aplica más dinero del que
/// efectivamente se recibió.
class AplicarPagoACuentaSobrepagoDelPago extends AplicarPagoACuentaResultado {
  AplicarPagoACuentaSobrepagoDelPago(this.montoDisponible);
  final int montoDisponible;
}

/// `monto` excede el `saldoPendiente` de la Cuenta — distinto del
/// sobrepago del Pago: aquí lo que se recibió alcanza, pero se
/// intentó aplicar más de lo que esa Cuenta debe.
class AplicarPagoACuentaSobrepagoDeLaCuenta extends AplicarPagoACuentaResultado {
  AplicarPagoACuentaSobrepagoDeLaCuenta(this.saldoDisponible);
  final int saldoDisponible;
}

class AplicarPagoACuentaErrorInesperado extends AplicarPagoACuentaResultado {
  AplicarPagoACuentaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Aplica dinero ya recibido (un `Pago` existente) a una Cuenta por
/// cobrar — Etapa 4J.2, modelo N:M. Pieza independiente pensada para
/// una futura pantalla de distribución de un mismo Pago entre varias
/// Cuentas; hoy también la usa internamente
/// `RegistrarPagoAplicadoUseCase` para el flujo simplificado de la
/// interfaz de esta etapa.
class AplicarPagoACuentaUseCase {
  AplicarPagoACuentaUseCase(this._pagoRepository, this._cuentaPorCobrarRepository);

  final PagoRepository _pagoRepository;
  final CuentaPorCobrarRepository _cuentaPorCobrarRepository;

  Future<AplicarPagoACuentaResultado> ejecutar({
    required String pagoId,
    required String cuentaPorCobrarId,
    required int monto,
    String? actorUsuarioId,
  }) async {
    final pago = await _pagoRepository.obtenerPorId(pagoId);
    if (pago == null) {
      return AplicarPagoACuentaPagoNoExiste();
    }
    if (EstatusPago.values.byName(pago.estatus) == EstatusPago.cancelado) {
      return AplicarPagoACuentaPagoCancelado();
    }
    if (monto <= 0) {
      return AplicarPagoACuentaMontoInvalido();
    }

    final montoSinAplicar = pago.montoTotal - pago.montoAplicado;
    if (monto > montoSinAplicar) {
      return AplicarPagoACuentaSobrepagoDelPago(montoSinAplicar);
    }

    final cuenta = await _cuentaPorCobrarRepository.obtenerPorId(cuentaPorCobrarId);
    if (cuenta == null) {
      return AplicarPagoACuentaCuentaNoExiste();
    }
    if (cuenta.clienteId != pago.clienteId) {
      return AplicarPagoACuentaClienteNoCoincide();
    }
    if (EstatusCuentaPorCobrar.values.byName(cuenta.estatus) == EstatusCuentaPorCobrar.pagada) {
      return AplicarPagoACuentaCuentaYaPagada();
    }
    if (monto > cuenta.saldoPendiente) {
      return AplicarPagoACuentaSobrepagoDeLaCuenta(cuenta.saldoPendiente);
    }

    try {
      final aplicacion = await _pagoRepository.aplicar(
        pagoId: pagoId,
        cuentaPorCobrarId: cuentaPorCobrarId,
        monto: monto,
        actorUsuarioId: actorUsuarioId,
      );
      return AplicarPagoACuentaExitoso(aplicacion);
    } catch (e) {
      return AplicarPagoACuentaErrorInesperado(e.toString());
    }
  }
}
