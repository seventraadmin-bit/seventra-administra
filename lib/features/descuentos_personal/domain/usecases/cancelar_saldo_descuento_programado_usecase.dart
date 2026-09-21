import 'package:riseg_one/features/descuentos_personal/data/tables/descuento_programado_empleado_table.dart'
    show EstatusDescuentoProgramado;

import '../repositories/descuento_programado_repository.dart';

sealed class CancelarSaldoDescuentoProgramadoResultado {}

class CancelarSaldoDescuentoProgramadoExitoso
    extends CancelarSaldoDescuentoProgramadoResultado {}

class CancelarSaldoDescuentoProgramadoNoExiste
    extends CancelarSaldoDescuentoProgramadoResultado {}

/// Solo se cancela un descuento `activo` — uno ya `liquidado` no tiene
/// saldo pendiente que condonar; uno ya `cancelado` no se cancela dos
/// veces.
class CancelarSaldoDescuentoProgramadoNoActivo
    extends CancelarSaldoDescuentoProgramadoResultado {}

class CancelarSaldoDescuentoProgramadoMotivoRequerido
    extends CancelarSaldoDescuentoProgramadoResultado {}

class CancelarSaldoDescuentoProgramadoErrorInesperado
    extends CancelarSaldoDescuentoProgramadoResultado {
  CancelarSaldoDescuentoProgramadoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Condona el saldo pendiente de una obligación (Etapa 15) — conserva
/// íntegro lo ya recuperado (cuotas `aplicada`), cancela solo las
/// cuotas futuras (`pendiente`/`reservada`, liberando primero
/// cualquier `reservada`). El historial deja constancia explícita de
/// que el saldo fue CANCELADO, nunca PAGADO. `motivo` obligatorio
/// (Resolución explícita de Marlon).
class CancelarSaldoDescuentoProgramadoUseCase {
  CancelarSaldoDescuentoProgramadoUseCase(this._repository);

  final DescuentoProgramadoRepository _repository;

  Future<CancelarSaldoDescuentoProgramadoResultado> ejecutar({
    required String descuentoProgramadoId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final descuento = await _repository.obtenerPorId(descuentoProgramadoId);
    if (descuento == null) return CancelarSaldoDescuentoProgramadoNoExiste();
    if (descuento.estatus != EstatusDescuentoProgramado.activo.name) {
      return CancelarSaldoDescuentoProgramadoNoActivo();
    }
    if (motivo.trim().isEmpty)
      return CancelarSaldoDescuentoProgramadoMotivoRequerido();

    try {
      await _repository.cancelarSaldo(
        descuentoProgramadoId: descuentoProgramadoId,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return CancelarSaldoDescuentoProgramadoExitoso();
    } catch (e) {
      return CancelarSaldoDescuentoProgramadoErrorInesperado(e.toString());
    }
  }
}
