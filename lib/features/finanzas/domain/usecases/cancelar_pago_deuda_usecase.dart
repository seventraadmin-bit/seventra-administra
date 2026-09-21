import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/diagnostico_error_inesperado.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';

import '../repositories/deuda_repository.dart';

sealed class CancelarPagoDeudaResultado {}

class CancelarPagoDeudaExitoso extends CancelarPagoDeudaResultado {
  CancelarPagoDeudaExitoso(this.resultado);
  final CancelacionPagoDeuda resultado;

  DeudaData get deuda => resultado.deuda;

  /// La UI lo usa para avisar que el ciclo de la tarjeta quedó sin
  /// deshacer y hay que revisarlo — nunca se resuelve en silencio.
  bool get cicloTarjetaRequiereConciliacion => resultado.cicloTarjetaRequiereConciliacion;
}

class CancelarPagoDeudaNoExiste extends CancelarPagoDeudaResultado {}

/// Segunda cancelación: resultado tipado, nunca una segunda reversión.
/// Es la protección explícita contra el doble conteo que pide el punto
/// 12 del pedido.
class CancelarPagoDeudaYaCancelado extends CancelarPagoDeudaResultado {}

class CancelarPagoDeudaDeudaCancelada extends CancelarPagoDeudaResultado {}

class CancelarPagoDeudaMotivoRequerido extends CancelarPagoDeudaResultado {}

class CancelarPagoDeudaErrorInesperado extends CancelarPagoDeudaResultado {
  CancelarPagoDeudaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cancela un pago individual ya registrado (Etapa 9), revirtiendo por
/// completo sus dos efectos inseparables: la Deuda recupera el saldo
/// que ese pago había abonado, y su `Egreso` se cancela, con lo que
/// Caja y bancos recupera exactamente el dinero. En una TDC eso
/// devuelve además el crédito disponible, siempre derivado de
/// `creditoDisponibleTarjeta` — nunca de una fórmula paralela.
///
/// El movimiento original NUNCA se borra ni se muta: la cancelación es
/// un `reversionPago` append-only vinculado por `movimientoOrigenId`.
/// De ahí se deriva "este pago está cancelado", así que una segunda
/// cancelación se corta aquí con [CancelarPagoDeudaYaCancelado] y jamás
/// llega a escribir una segunda reversión.
///
/// **Nunca toca los CARGOS de la tarjeta** (punto 10 del pedido): una
/// Compra, un Tiempo Extra o un Egreso manual financiados con esa TDC
/// conservan íntegros su cargo y su `egresoGastoId`. Esta operación
/// solo mira `MovimientoDeuda(tipo: pago)` y su `egresoId`. Las dos
/// relaciones son distintas por diseño y no se mezclan:
/// `egresoId` = el Egreso que este PAGO generó;
/// `egresoGastoId` = el Egreso-documento de un GASTO financiado con la
/// tarjeta.
class CancelarPagoDeudaUseCase {
  CancelarPagoDeudaUseCase(this._repository);

  final DeudaRepository _repository;

  Future<CancelarPagoDeudaResultado> ejecutar({
    required int pagoId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final estado = await _repository.obtenerEstadoPago(pagoId);
    if (!estado.existe) return CancelarPagoDeudaNoExiste();
    if (estado.cancelado) return CancelarPagoDeudaYaCancelado();

    final pago = (await _repository.obtenerMovimiento(pagoId))!;
    final deuda = await _repository.obtenerPorId(pago.deudaId);
    if (deuda == null) return CancelarPagoDeudaNoExiste();
    if (EstatusDeuda.values.byName(deuda.estatus) == EstatusDeuda.cancelada) {
      return CancelarPagoDeudaDeudaCancelada();
    }
    if (!motivoEsValido(motivo)) return CancelarPagoDeudaMotivoRequerido();

    try {
      final resultado = await _repository.cancelarPago(
        pagoId: pagoId,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return CancelarPagoDeudaExitoso(resultado);
    } catch (e, s) {
      return CancelarPagoDeudaErrorInesperado(
        diagnosticoErrorInesperado(e, s, contexto: 'CancelarPagoDeudaUseCase'),
      );
    }
  }
}
