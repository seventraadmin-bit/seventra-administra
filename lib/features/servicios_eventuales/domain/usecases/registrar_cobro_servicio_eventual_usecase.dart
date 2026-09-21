import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_aplicado_usecase.dart';

import '../repositories/servicio_eventual_repository.dart';

sealed class RegistrarCobroServicioEventualResultado {}

class RegistrarCobroServicioEventualExitoso extends RegistrarCobroServicioEventualResultado {
  RegistrarCobroServicioEventualExitoso(this.pago);
  final RegistrarPagoAplicadoExitoso pago;
}

class RegistrarCobroServicioEventualNoExiste extends RegistrarCobroServicioEventualResultado {}

/// El eventual no tiene Cuenta por cobrar — sólo puede pasarle al
/// histórico anterior a la schemaVersion 88.
class RegistrarCobroServicioEventualSinCuenta extends RegistrarCobroServicioEventualResultado {}

/// Traduce el rechazo del flujo de Pagos sin reinventarlo: el motivo
/// real viene de `RegistrarPagoAplicadoUseCase`, que es quien conoce
/// saldo, estatus y sobrepago.
class RegistrarCobroServicioEventualRechazado extends RegistrarCobroServicioEventualResultado {
  RegistrarCobroServicioEventualRechazado(this.motivo);
  final RegistrarPagoAplicadoResultado motivo;
}

class RegistrarCobroServicioEventualErrorInesperado extends RegistrarCobroServicioEventualResultado {
  RegistrarCobroServicioEventualErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cobra un eventual **después** de venderlo.
///
/// No implementa nada de cobranza: localiza la Cuenta por cobrar del
/// eventual y delega en el flujo real de Pagos, el mismo que usa la
/// cobranza recurrente. Por eso el pago parcial funciona sin una sola
/// regla nueva — `AplicacionPago` ya lo soportaba.
class RegistrarCobroServicioEventualUseCase {
  RegistrarCobroServicioEventualUseCase(this._repository, this._registrarPagoAplicado);

  final ServicioEventualRepository _repository;
  final RegistrarPagoAplicadoUseCase _registrarPagoAplicado;

  Future<RegistrarCobroServicioEventualResultado> ejecutar({
    required String servicioEventualId,
    required int monto,
    required DateTime fechaPago,
    required String formaPago,
    String? cuentaFinancieraId,
    String? referencia,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    final eventual = await _repository.obtenerPorId(servicioEventualId);
    if (eventual == null) return RegistrarCobroServicioEventualNoExiste();

    final cuenta = await _repository.obtenerCuentaPorCobrar(servicioEventualId);
    if (cuenta == null) return RegistrarCobroServicioEventualSinCuenta();

    try {
      final resultado = await _registrarPagoAplicado.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        monto: monto,
        fechaPago: fechaPago,
        formaPago: formaPago,
        cuentaFinancieraId: cuentaFinancieraId,
        referencia: referencia,
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );
      if (resultado is RegistrarPagoAplicadoExitoso) {
        return RegistrarCobroServicioEventualExitoso(resultado);
      }
      return RegistrarCobroServicioEventualRechazado(resultado);
    } catch (e) {
      return RegistrarCobroServicioEventualErrorInesperado(e.toString());
    }
  }
}
