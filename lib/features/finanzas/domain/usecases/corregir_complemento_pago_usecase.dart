import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/complemento_pago_table.dart';

import '../repositories/complemento_pago_repository.dart';

sealed class CorregirComplementoPagoResultado {}

class CorregirComplementoPagoExitoso extends CorregirComplementoPagoResultado {
  CorregirComplementoPagoExitoso(this.complemento);
  final ComplementoPagoData complemento;
}

class CorregirComplementoPagoNoExiste extends CorregirComplementoPagoResultado {}

class CorregirComplementoPagoCancelado extends CorregirComplementoPagoResultado {}

class CorregirComplementoPagoErrorInesperado extends CorregirComplementoPagoResultado {
  CorregirComplementoPagoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige metadatos administrativos de un Complemento — nunca `uuid`
/// ni `montoTotal` (Etapa 4J.3, Resolución de Marlon: mismo criterio
/// que `Pago`, cancelar y volver a registrar). Requiere `motivo`.
class CorregirComplementoPagoUseCase {
  CorregirComplementoPagoUseCase(this._repository);

  final ComplementoPagoRepository _repository;

  Future<CorregirComplementoPagoResultado> ejecutar({
    required String complementoPagoId,
    String? serieFiscal,
    String? folioFiscal,
    DateTime? fechaTimbrado,
    String? observaciones,
    required String motivo,
    String? actor,
  }) async {
    final complemento = await _repository.obtenerPorId(complementoPagoId);
    if (complemento == null) {
      return CorregirComplementoPagoNoExiste();
    }
    if (EstatusComplementoPago.values.byName(complemento.estatus) == EstatusComplementoPago.cancelado) {
      return CorregirComplementoPagoCancelado();
    }

    try {
      final actualizado = await _repository.corregir(
        complementoPagoId: complementoPagoId,
        serieFiscal: serieFiscal,
        folioFiscal: folioFiscal,
        fechaTimbrado: fechaTimbrado,
        observaciones: observaciones,
        motivo: motivo,
        actor: actor,
      );
      return CorregirComplementoPagoExitoso(actualizado);
    } catch (e) {
      return CorregirComplementoPagoErrorInesperado(e.toString());
    }
  }
}
