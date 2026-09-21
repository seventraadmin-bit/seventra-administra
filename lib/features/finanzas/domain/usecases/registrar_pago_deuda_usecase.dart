import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';

import '../repositories/deuda_repository.dart';

sealed class RegistrarPagoDeudaResultado {}

class RegistrarPagoDeudaExitoso extends RegistrarPagoDeudaResultado {
  RegistrarPagoDeudaExitoso(this.deuda);
  final DeudaData deuda;
}

class RegistrarPagoDeudaNoExiste extends RegistrarPagoDeudaResultado {}

class RegistrarPagoDeudaNoActiva extends RegistrarPagoDeudaResultado {}

class RegistrarPagoDeudaImporteInvalido extends RegistrarPagoDeudaResultado {}

/// `importe` excede el `saldoActual` de la Deuda.
class RegistrarPagoDeudaSobrepasaSaldo extends RegistrarPagoDeudaResultado {
  RegistrarPagoDeudaSobrepasaSaldo(this.saldoActual);
  final int saldoActual;
}

class RegistrarPagoDeudaErrorInesperado extends RegistrarPagoDeudaResultado {
  RegistrarPagoDeudaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra un pago sobre una Deuda activa (Etapa 19) — en una sola
/// transacción (`DeudaRepository.registrarPago`): crea el `Egreso` real
/// de la salida de efectivo, el `MovimientoDeuda` tipo `pago`, y
/// actualiza `saldoActual`/`estatus` (→ `liquidada` si llega a 0).
/// Bloquea estrictamente cualquier intento de pagar más del saldo
/// actual — nada se muta si falla.
class RegistrarPagoDeudaUseCase {
  RegistrarPagoDeudaUseCase(this._repository, this._generarCodigo);

  final DeudaRepository _repository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<RegistrarPagoDeudaResultado> ejecutar({
    required String deudaId,
    required DateTime fecha,
    required int importe,
    required String formaPago,
    String? cuentaCaja,
    String? cuentaFinancieraId,
    String? referencia,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    final deuda = await _repository.obtenerPorId(deudaId);
    if (deuda == null) return RegistrarPagoDeudaNoExiste();
    if (EstatusDeuda.values.byName(deuda.estatus) != EstatusDeuda.activa) return RegistrarPagoDeudaNoActiva();
    if (importe <= 0) return RegistrarPagoDeudaImporteInvalido();
    if (importe > deuda.saldoActual) return RegistrarPagoDeudaSobrepasaSaldo(deuda.saldoActual);

    try {
      final folioResultado = await _generarCodigo.ejecutar('egreso');
      final String folioEgreso;
      switch (folioResultado) {
        case Ok<String>(value: final v):
          folioEgreso = v;
        case Err<String>(failure: final f):
          return RegistrarPagoDeudaErrorInesperado(f.message);
      }

      final actualizada = await _repository.registrarPago(
        deudaId: deudaId,
        folioEgreso: folioEgreso,
        fecha: fecha,
        importe: importe,
        formaPago: formaPago,
        cuentaCaja: cuentaCaja,
        cuentaFinancieraId: cuentaFinancieraId,
        referencia: referencia,
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );
      return RegistrarPagoDeudaExitoso(actualizada);
    } on SaldoInsuficienteException {
      // Un saldo insuficiente NO es un error inesperado: es un
      // rechazo previsto y accionable. Se deja propagar para que la
      // pantalla muestre disponible/requerido/faltante en vez de un
      // mensaje genérico. La transacción ya quedó revertida entera.
      rethrow;
    } catch (e) {
      return RegistrarPagoDeudaErrorInesperado(e.toString());
    }
  }
}
