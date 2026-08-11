import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';

import '../repositories/pago_repository.dart';

sealed class CancelarAplicacionPagoResultado {}

class CancelarAplicacionPagoExitoso extends CancelarAplicacionPagoResultado {
  CancelarAplicacionPagoExitoso(this.aplicacion);
  final AplicacionPagoData aplicacion;
}

class CancelarAplicacionPagoNoExiste extends CancelarAplicacionPagoResultado {}

class CancelarAplicacionPagoYaCancelada extends CancelarAplicacionPagoResultado {}

class CancelarAplicacionPagoErrorInesperado extends CancelarAplicacionPagoResultado {
  CancelarAplicacionPagoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cancela una aplicación individual (Etapa 4J.2) — revierte su efecto
/// sobre la Cuenta afectada y libera el monto de vuelta al Pago
/// (`montoAplicado` baja, queda disponible para aplicarse de nuevo).
/// Nunca borra la fila (Resolución 6 de Marlon). Requiere `motivo`.
class CancelarAplicacionPagoUseCase {
  CancelarAplicacionPagoUseCase(this._repository);

  final PagoRepository _repository;

  Future<CancelarAplicacionPagoResultado> ejecutar({
    required String aplicacionPagoId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final aplicacion = await _repository.obtenerAplicacionPorId(aplicacionPagoId);
    if (aplicacion == null) {
      return CancelarAplicacionPagoNoExiste();
    }
    if (EstatusAplicacionPago.values.byName(aplicacion.estatus) == EstatusAplicacionPago.cancelada) {
      return CancelarAplicacionPagoYaCancelada();
    }

    try {
      final actualizada = await _repository.cancelarAplicacion(
        aplicacionPagoId: aplicacionPagoId,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return CancelarAplicacionPagoExitoso(actualizada);
    } catch (e) {
      return CancelarAplicacionPagoErrorInesperado(e.toString());
    }
  }
}
