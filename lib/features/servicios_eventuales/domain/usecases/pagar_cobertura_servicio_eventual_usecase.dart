import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';

import '../../data/tables/servicio_eventual_table.dart';
import '../repositories/servicio_eventual_repository.dart';

sealed class PagarCoberturaServicioEventualResultado {}

class PagarCoberturaServicioEventualExitoso extends PagarCoberturaServicioEventualResultado {
  PagarCoberturaServicioEventualExitoso(this.cobertura);
  final ServicioEventualCoberturaData cobertura;
}

class PagarCoberturaServicioEventualNoExiste extends PagarCoberturaServicioEventualResultado {}

class PagarCoberturaServicioEventualYaPagada extends PagarCoberturaServicioEventualResultado {}

class PagarCoberturaServicioEventualCancelada extends PagarCoberturaServicioEventualResultado {}

/// Falta el origen del dinero: ni cuenta ni tarjeta.
class PagarCoberturaServicioEventualOrigenFinancieroRequerido
    extends PagarCoberturaServicioEventualResultado {}

/// Llegaron cuenta Y tarjeta a la vez.
class PagarCoberturaServicioEventualOrigenFinancieroAmbiguo
    extends PagarCoberturaServicioEventualResultado {}

class PagarCoberturaServicioEventualTarjetaInvalida extends PagarCoberturaServicioEventualResultado {}

class PagarCoberturaServicioEventualTarjetaSinLimiteConfigurado
    extends PagarCoberturaServicioEventualResultado {}

class PagarCoberturaServicioEventualTarjetaExcedeLimite extends PagarCoberturaServicioEventualResultado {
  PagarCoberturaServicioEventualTarjetaExcedeLimite(this.disponible);
  final int disponible;
}

class PagarCoberturaServicioEventualErrorInesperado extends PagarCoberturaServicioEventualResultado {
  PagarCoberturaServicioEventualErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Paga a quien cubrió — el único punto de este dominio donde sale
/// dinero de verdad.
///
/// **Exactamente un origen financiero, obligatorio en dominio.** Con
/// Cuenta se crea un Egreso y nada más; con tarjeta se registra el
/// cargo en la Deuda y **no** se crea Egreso, porque el dinero no ha
/// salido todavía: saldrá al pagar la tarjeta. Mismo criterio estricto
/// que las Recargas de Telefonía: que Compras y Tiempos Extra acepten
/// "cuenta sin especificar" no es razón para aceptarlo aquí, y el
/// `CHECK` del esquema (`estatus <> 'pagada' OR egreso_id IS NOT NULL
/// OR deuda_id IS NOT NULL`) lo respalda.
class PagarCoberturaServicioEventualUseCase {
  PagarCoberturaServicioEventualUseCase(this._repository, this._deudaRepository);

  final ServicioEventualRepository _repository;
  final DeudaRepository _deudaRepository;

  Future<PagarCoberturaServicioEventualResultado> ejecutar({
    required String coberturaId,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
    String? actorUsuarioId,
  }) async {
    final cobertura = await _repository.obtenerCobertura(coberturaId);
    if (cobertura == null) return PagarCoberturaServicioEventualNoExiste();
    if (cobertura.estatus == EstatusEjecucionServicioEventual.pagada.name) {
      return PagarCoberturaServicioEventualYaPagada();
    }
    if (cobertura.estatus == EstatusEjecucionServicioEventual.cancelada.name) {
      return PagarCoberturaServicioEventualCancelada();
    }

    if (formaPago.trim().isEmpty) return PagarCoberturaServicioEventualOrigenFinancieroRequerido();
    final esTarjeta = formaPago == FormaPago.tarjeta.name;
    final tieneCuenta = (cuentaFinancieraId ?? '').isNotEmpty;
    final tieneTarjeta = (deudaIdTarjeta ?? '').isNotEmpty;

    if (tieneCuenta && tieneTarjeta) return PagarCoberturaServicioEventualOrigenFinancieroAmbiguo();
    if (esTarjeta) {
      if (!tieneTarjeta) return PagarCoberturaServicioEventualOrigenFinancieroRequerido();
      final tarjeta = await _deudaRepository.obtenerPorId(deudaIdTarjeta!);
      final validacion = validarOrigenTarjeta(tarjeta: tarjeta, monto: cobertura.importeAcordado);
      switch (validacion.error) {
        case ErrorOrigenTarjeta.noEsTarjetaActiva:
          return PagarCoberturaServicioEventualTarjetaInvalida();
        case ErrorOrigenTarjeta.sinLimiteConfigurado:
          return PagarCoberturaServicioEventualTarjetaSinLimiteConfigurado();
        case ErrorOrigenTarjeta.excedeLimite:
          return PagarCoberturaServicioEventualTarjetaExcedeLimite(validacion.disponible!);
        case null:
          break;
      }
    } else if (!tieneCuenta) {
      return PagarCoberturaServicioEventualOrigenFinancieroRequerido();
    }

    try {
      final pagada = await _repository.pagarCobertura(
        coberturaId: coberturaId,
        formaPago: formaPago,
        cuentaFinancieraId: esTarjeta ? null : cuentaFinancieraId,
        deudaId: esTarjeta ? deudaIdTarjeta : null,
        actorUsuarioId: actorUsuarioId,
      );
      return PagarCoberturaServicioEventualExitoso(pagada);
    } on SaldoInsuficienteException {
      // Un saldo insuficiente NO es un error inesperado: es un
      // rechazo previsto y accionable. Se deja propagar para que la
      // pantalla muestre disponible/requerido/faltante en vez de un
      // mensaje genérico. La transacción ya quedó revertida entera.
      rethrow;
    } catch (e) {
      return PagarCoberturaServicioEventualErrorInesperado(e.toString());
    }
  }
}
