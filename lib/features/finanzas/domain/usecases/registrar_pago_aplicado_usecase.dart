import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart';

import '../repositories/cuenta_por_cobrar_repository.dart';
import '../repositories/pago_repository.dart';

sealed class RegistrarPagoAplicadoResultado {}

class RegistrarPagoAplicadoExitoso extends RegistrarPagoAplicadoResultado {
  RegistrarPagoAplicadoExitoso(this.pago, this.aplicacion);
  final PagoData pago;
  final AplicacionPagoData aplicacion;
}

class RegistrarPagoAplicadoCuentaNoExiste extends RegistrarPagoAplicadoResultado {}

class RegistrarPagoAplicadoCuentaYaPagada extends RegistrarPagoAplicadoResultado {}

/// La CxC está `cancelada` (Etapa 7) — nunca se le aplica un Pago
/// nuevo, la obligación en sí fue anulada.
class RegistrarPagoAplicadoCuentaCancelada extends RegistrarPagoAplicadoResultado {}

class RegistrarPagoAplicadoMontoInvalido extends RegistrarPagoAplicadoResultado {}

/// `monto` excede el `saldoPendiente` de la Cuenta.
class RegistrarPagoAplicadoSobrepago extends RegistrarPagoAplicadoResultado {
  RegistrarPagoAplicadoSobrepago(this.saldoDisponible);
  final int saldoDisponible;
}

class RegistrarPagoAplicadoErrorInesperado extends RegistrarPagoAplicadoResultado {
  RegistrarPagoAplicadoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Flujo simplificado que expone la interfaz de la Etapa 4J.2:
/// registra un Pago aplicado por completo a una sola Cuenta por
/// cobrar, en un solo paso de usuario. Internamente crea el `Pago` y
/// su única `AplicacionPago` en una sola transacción
/// (`PagoRepository.crearAplicado`) — nunca dos llamadas separadas,
/// para que un sobrepago rechazado nunca deje un Pago huérfano sin
/// aplicaciones.
///
/// La distribución de un mismo Pago entre varias Cuentas queda fuera
/// de esta etapa (usa en su lugar `RegistrarPagoUseCase` +
/// `AplicarPagoACuentaUseCase` por separado, ya listos para esa
/// pantalla futura).
class RegistrarPagoAplicadoUseCase {
  RegistrarPagoAplicadoUseCase(this._pagoRepository, this._cuentaPorCobrarRepository, this._generarCodigo);

  final PagoRepository _pagoRepository;
  final CuentaPorCobrarRepository _cuentaPorCobrarRepository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<RegistrarPagoAplicadoResultado> ejecutar({
    required String cuentaPorCobrarId,
    required int monto,
    required DateTime fechaPago,
    required String formaPago,
    String? referencia,
    String? bancoOrigen,
    String? cuentaBancariaDestino,
    String? cuentaFinancieraId,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    final cuenta = await _cuentaPorCobrarRepository.obtenerPorId(cuentaPorCobrarId);
    if (cuenta == null) {
      return RegistrarPagoAplicadoCuentaNoExiste();
    }
    if (monto <= 0) {
      return RegistrarPagoAplicadoMontoInvalido();
    }
    if (EstatusCuentaPorCobrar.values.byName(cuenta.estatus) == EstatusCuentaPorCobrar.pagada) {
      return RegistrarPagoAplicadoCuentaYaPagada();
    }
    if (EstatusCuentaPorCobrar.values.byName(cuenta.estatus) == EstatusCuentaPorCobrar.cancelada) {
      return RegistrarPagoAplicadoCuentaCancelada();
    }
    if (monto > cuenta.saldoPendiente) {
      return RegistrarPagoAplicadoSobrepago(cuenta.saldoPendiente);
    }

    try {
      final codigoResultado = await _generarCodigo.ejecutar('pago');
      final folioPago = codigoResultado.when(ok: (c) => c, failure: (f) => throw StateError(f.message));

      final resultado = await _pagoRepository.crearAplicado(
        folioPago: folioPago,
        // La contraparte del Pago NO se captura: se deriva de la
        // Cuenta, que a su vez la derivó de su origen. Por eso los dos
        // campos nunca pueden contradecirse.
        clienteId: cuenta.clienteId,
        servicioEventualId: cuenta.servicioEventualId,
        montoTotal: monto,
        fechaPago: fechaPago,
        formaPago: formaPago,
        cuentaPorCobrarId: cuentaPorCobrarId,
        referencia: referencia,
        bancoOrigen: bancoOrigen,
        cuentaBancariaDestino: cuentaBancariaDestino,
        cuentaFinancieraId: cuentaFinancieraId,
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );
      return RegistrarPagoAplicadoExitoso(resultado.pago, resultado.aplicacion);
    } catch (e) {
      return RegistrarPagoAplicadoErrorInesperado(e.toString());
    }
  }
}
