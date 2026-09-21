import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';

import '../repositories/deuda_repository.dart';

sealed class CancelarDeudaResultado {}

class CancelarDeudaExitoso extends CancelarDeudaResultado {
  CancelarDeudaExitoso(this.deuda);
  final DeudaData deuda;
}

class CancelarDeudaNoExiste extends CancelarDeudaResultado {}

class CancelarDeudaNoActiva extends CancelarDeudaResultado {}

class CancelarDeudaMotivoRequerido extends CancelarDeudaResultado {}

class CancelarDeudaErrorInesperado extends CancelarDeudaResultado {
  CancelarDeudaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cancela (condona) el saldo restante de una Deuda activa (Etapa 19)
/// — el historial (`MovimientoDeuda`) nunca se borra, mismo criterio
/// que `DescuentoProgramado.cancelarSaldo`. Sin `Egreso`: lo que queda
/// pendiente se da por perdonado, no pagado.
class CancelarDeudaUseCase {
  CancelarDeudaUseCase(this._repository);

  final DeudaRepository _repository;

  Future<CancelarDeudaResultado> ejecutar({
    required String deudaId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final deuda = await _repository.obtenerPorId(deudaId);
    if (deuda == null) return CancelarDeudaNoExiste();
    if (EstatusDeuda.values.byName(deuda.estatus) != EstatusDeuda.activa) return CancelarDeudaNoActiva();
    if (motivo.trim().isEmpty) return CancelarDeudaMotivoRequerido();

    try {
      final actualizada = await _repository.cancelar(
        deudaId: deudaId,
        motivo: motivo.trim(),
        actorUsuarioId: actorUsuarioId,
      );
      return CancelarDeudaExitoso(actualizada);
    } catch (e) {
      return CancelarDeudaErrorInesperado(e.toString());
    }
  }
}
