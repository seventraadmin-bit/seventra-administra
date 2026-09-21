import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';

import '../../data/tables/servicio_eventual_table.dart';
import '../repositories/servicio_eventual_repository.dart';

sealed class PagarCostoServicioEventualResultado {}

class PagarCostoServicioEventualExitoso extends PagarCostoServicioEventualResultado {
  PagarCostoServicioEventualExitoso(this.costo);
  final ServicioEventualCostoData costo;
}

class PagarCostoServicioEventualNoExiste extends PagarCostoServicioEventualResultado {}

class PagarCostoServicioEventualYaPagado extends PagarCostoServicioEventualResultado {}

class PagarCostoServicioEventualCancelado extends PagarCostoServicioEventualResultado {}

class PagarCostoServicioEventualOrigenFinancieroRequerido extends PagarCostoServicioEventualResultado {}

class PagarCostoServicioEventualOrigenFinancieroAmbiguo extends PagarCostoServicioEventualResultado {}

class PagarCostoServicioEventualTarjetaInvalida extends PagarCostoServicioEventualResultado {}

class PagarCostoServicioEventualTarjetaSinLimiteConfigurado extends PagarCostoServicioEventualResultado {}

class PagarCostoServicioEventualTarjetaExcedeLimite extends PagarCostoServicioEventualResultado {
  PagarCostoServicioEventualTarjetaExcedeLimite(this.disponible);
  final int disponible;
}

class PagarCostoServicioEventualErrorInesperado extends PagarCostoServicioEventualResultado {
  PagarCostoServicioEventualErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Paga un costo adicional del evento.
///
/// Origen **independiente** del de cualquier otro costo y del de las
/// coberturas: dos gastos del mismo evento pagados con la misma tarjeta
/// producen dos cargos, nunca uno fusionado. Mismo criterio que los
/// costos adicionales de Tiempo Extra.
class PagarCostoServicioEventualUseCase {
  PagarCostoServicioEventualUseCase(this._repository, this._deudaRepository);

  final ServicioEventualRepository _repository;
  final DeudaRepository _deudaRepository;

  Future<PagarCostoServicioEventualResultado> ejecutar({
    required String costoId,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
    String? actorUsuarioId,
  }) async {
    final costo = await _repository.obtenerCosto(costoId);
    if (costo == null) return PagarCostoServicioEventualNoExiste();
    if (costo.estatus == EstatusEjecucionServicioEventual.pagada.name) {
      return PagarCostoServicioEventualYaPagado();
    }
    if (costo.estatus == EstatusEjecucionServicioEventual.cancelada.name) {
      return PagarCostoServicioEventualCancelado();
    }

    if (formaPago.trim().isEmpty) return PagarCostoServicioEventualOrigenFinancieroRequerido();
    final esTarjeta = formaPago == FormaPago.tarjeta.name;
    final tieneCuenta = (cuentaFinancieraId ?? '').isNotEmpty;
    final tieneTarjeta = (deudaIdTarjeta ?? '').isNotEmpty;

    if (tieneCuenta && tieneTarjeta) return PagarCostoServicioEventualOrigenFinancieroAmbiguo();
    if (esTarjeta) {
      if (!tieneTarjeta) return PagarCostoServicioEventualOrigenFinancieroRequerido();
      final tarjeta = await _deudaRepository.obtenerPorId(deudaIdTarjeta!);
      final validacion = validarOrigenTarjeta(tarjeta: tarjeta, monto: costo.monto);
      switch (validacion.error) {
        case ErrorOrigenTarjeta.noEsTarjetaActiva:
          return PagarCostoServicioEventualTarjetaInvalida();
        case ErrorOrigenTarjeta.sinLimiteConfigurado:
          return PagarCostoServicioEventualTarjetaSinLimiteConfigurado();
        case ErrorOrigenTarjeta.excedeLimite:
          return PagarCostoServicioEventualTarjetaExcedeLimite(validacion.disponible!);
        case null:
          break;
      }
    } else if (!tieneCuenta) {
      return PagarCostoServicioEventualOrigenFinancieroRequerido();
    }

    try {
      final pagado = await _repository.pagarCosto(
        costoId: costoId,
        formaPago: formaPago,
        cuentaFinancieraId: esTarjeta ? null : cuentaFinancieraId,
        deudaId: esTarjeta ? deudaIdTarjeta : null,
        actorUsuarioId: actorUsuarioId,
      );
      return PagarCostoServicioEventualExitoso(pagado);
    } on SaldoInsuficienteException {
      // Un saldo insuficiente NO es un error inesperado: es un
      // rechazo previsto y accionable. Se deja propagar para que la
      // pantalla muestre disponible/requerido/faltante en vez de un
      // mensaje genérico. La transacción ya quedó revertida entera.
      rethrow;
    } catch (e) {
      return PagarCostoServicioEventualErrorInesperado(e.toString());
    }
  }
}
