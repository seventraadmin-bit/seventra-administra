import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';

import '../repositories/pago_repository.dart';

sealed class CorregirPagoResultado {}

class CorregirPagoExitoso extends CorregirPagoResultado {
  CorregirPagoExitoso(this.pago);
  final PagoData pago;
}

class CorregirPagoNoExiste extends CorregirPagoResultado {}

/// Un Pago cancelado no admite correcciones — cancélese/vuélvase a
/// capturar si el error está en el monto, o regístrese uno nuevo.
class CorregirPagoCancelado extends CorregirPagoResultado {}

class CorregirPagoErrorInesperado extends CorregirPagoResultado {
  CorregirPagoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige metadatos administrativos de un Pago — nunca `montoTotal`
/// (Etapa 4J.2). Requiere `motivo`, igual que cualquier corrección
/// administrativa ya existente en el proyecto.
class CorregirPagoUseCase {
  CorregirPagoUseCase(this._repository);

  final PagoRepository _repository;

  Future<CorregirPagoResultado> ejecutar({
    required String pagoId,
    DateTime? fechaPago,
    String? formaPago,
    String? referencia,
    String? bancoOrigen,
    String? cuentaBancariaDestino,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final pago = await _repository.obtenerPorId(pagoId);
    if (pago == null) {
      return CorregirPagoNoExiste();
    }
    if (EstatusPago.values.byName(pago.estatus) == EstatusPago.cancelado) {
      return CorregirPagoCancelado();
    }

    try {
      final actualizado = await _repository.corregir(
        pagoId: pagoId,
        fechaPago: fechaPago,
        formaPago: formaPago,
        referencia: referencia,
        bancoOrigen: bancoOrigen,
        cuentaBancariaDestino: cuentaBancariaDestino,
        observaciones: observaciones,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return CorregirPagoExitoso(actualizado);
    } catch (e) {
      return CorregirPagoErrorInesperado(e.toString());
    }
  }
}
