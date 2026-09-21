import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/diagnostico_error_inesperado.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';

import '../repositories/deuda_repository.dart';

sealed class CorregirPagoDeudaResultado {}

class CorregirPagoDeudaExitoso extends CorregirPagoDeudaResultado {
  CorregirPagoDeudaExitoso(this.deuda);
  final DeudaData deuda;
}

/// El id no corresponde a ningún movimiento, o corresponde a uno que no
/// es un pago (un cargo, un ajuste, el alta inicial).
class CorregirPagoDeudaNoExiste extends CorregirPagoDeudaResultado {}

/// El pago ya fue cancelado — corregir el monto de algo que ya no
/// existe financieramente no significa nada. Hay que registrar un pago
/// nuevo.
class CorregirPagoDeudaCancelado extends CorregirPagoDeudaResultado {}

/// La Deuda entera está cancelada (condonada): su historial queda
/// congelado.
class CorregirPagoDeudaDeudaCancelada extends CorregirPagoDeudaResultado {}

class CorregirPagoDeudaMotivoRequerido extends CorregirPagoDeudaResultado {}

class CorregirPagoDeudaImporteInvalido extends CorregirPagoDeudaResultado {}

/// Subir el pago a [importeMaximo] o menos es posible; más, no: dejaría
/// la Deuda con saldo negativo. Ver el doc comment del use case para
/// por qué el máximo NO es simplemente el saldo actual.
class CorregirPagoDeudaSobrepasaSaldo extends CorregirPagoDeudaResultado {
  CorregirPagoDeudaSobrepasaSaldo(this.importeMaximo);
  final int importeMaximo;
}

class CorregirPagoDeudaErrorInesperado extends CorregirPagoDeudaResultado {
  CorregirPagoDeudaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige un pago individual ya registrado (Etapa 9) — su monto, la
/// `CuentaFinanciera` de la que salió, o ambos a la vez, en una sola
/// transacción.
///
/// Un pago tiene dos efectos inseparables: reduce la obligación y saca
/// dinero de una cuenta. Por eso `MovimientoDeuda(tipo: pago)` y su
/// `Egreso` deben representar SIEMPRE la misma realidad, y esta
/// corrección los mueve juntos — nunca uno sin el otro. La vía inversa
/// (corregir ese Egreso desde Finanzas) sigue bloqueada por
/// `CorregirEgresoUseCase`: el pago se corrige desde su origen, la
/// Deuda, y nunca desde el Egreso que generó.
///
/// **Sobrepago (punto 7 del pedido).** Subir el monto se rechaza si
/// dejaría la Deuda en negativo. El máximo NO es el saldo actual a
/// secas: este pago ya ocupa parte de la historia del saldo, así que el
/// tope real es `saldoActual + importeNetoDeEstePago` — comparar
/// ingenuamente contra el saldo haría imposible subir el monto de un
/// pago que ya dejó la deuda en cero. Mismo criterio que
/// `CorregirEgresoUseCase` con `netoAportadoPorEgreso`. Nunca se crea
/// saldo a favor, devolución, Ingreso ni crédito futuro — ni siquiera
/// en TDC, donde la arquitectura tampoco contempla saldo acreedor.
///
/// **Ciclo de TDC**: corregir el monto NUNCA mueve
/// `tarjetaVencimientoCubiertoHasta`. Bajo la regla vigente —aprobada
/// explícitamente por Marlon en esta etapa— el ciclo lo cubre el hecho
/// de haber pagado, no el monto: el monto no participa, así que
/// corregirlo no puede descubrir un ciclo que nunca dependió de él.
class CorregirPagoDeudaUseCase {
  CorregirPagoDeudaUseCase(this._repository);

  final DeudaRepository _repository;

  Future<CorregirPagoDeudaResultado> ejecutar({
    required int pagoId,
    int? nuevoImporte,
    String? nuevaCuentaFinancieraId,
    bool limpiarCuentaFinanciera = false,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final estado = await _repository.obtenerEstadoPago(pagoId);
    if (!estado.existe) return CorregirPagoDeudaNoExiste();
    if (estado.cancelado) return CorregirPagoDeudaCancelado();

    final pago = (await _repository.obtenerMovimiento(pagoId))!;
    final deuda = await _repository.obtenerPorId(pago.deudaId);
    if (deuda == null) return CorregirPagoDeudaNoExiste();
    if (EstatusDeuda.values.byName(deuda.estatus) == EstatusDeuda.cancelada) {
      return CorregirPagoDeudaDeudaCancelada();
    }
    if (!motivoEsValido(motivo)) return CorregirPagoDeudaMotivoRequerido();

    if (nuevoImporte != null) {
      if (nuevoImporte <= 0) return CorregirPagoDeudaImporteInvalido();
      final importeMaximo = deuda.saldoActual + estado.importeNeto;
      if (nuevoImporte > importeMaximo) {
        return CorregirPagoDeudaSobrepasaSaldo(importeMaximo);
      }
    }

    try {
      final actualizada = await _repository.corregirPago(
        pagoId: pagoId,
        nuevoImporte: nuevoImporte,
        nuevaCuentaFinancieraId: nuevaCuentaFinancieraId,
        limpiarCuentaFinanciera: limpiarCuentaFinanciera,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return CorregirPagoDeudaExitoso(actualizada);
    } on SaldoInsuficienteException {
      // Corregir también puede quedarse sin saldo (subir el importe, o
      // mover la salida a otra cuenta). No es un error inesperado: se
      // deja propagar para que la pantalla muestre los tres números.
      rethrow;
    } catch (e, s) {
      return CorregirPagoDeudaErrorInesperado(
        diagnosticoErrorInesperado(e, s, contexto: 'CorregirPagoDeudaUseCase'),
      );
    }
  }
}
