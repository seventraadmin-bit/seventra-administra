import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/cuenta_por_cobrar_repository.dart';

sealed class ActualizarFechaVencimientoCuentaPorCobrarResultado {}

class ActualizarFechaVencimientoCuentaPorCobrarExitoso extends ActualizarFechaVencimientoCuentaPorCobrarResultado {
  ActualizarFechaVencimientoCuentaPorCobrarExitoso(this.cuenta);
  final CuentaPorCobrarData cuenta;
}

class ActualizarFechaVencimientoCuentaPorCobrarNoExiste extends ActualizarFechaVencimientoCuentaPorCobrarResultado {}

class ActualizarFechaVencimientoCuentaPorCobrarErrorInesperado extends ActualizarFechaVencimientoCuentaPorCobrarResultado {
  ActualizarFechaVencimientoCuentaPorCobrarErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Completa o corrige `fechaVencimiento` de una Cuenta por cobrar
/// (Etapa 4J.1, Resolución E de Marlon) — la única vía para las
/// cuentas que nacieron sin fecha (documento de origen sin regla de
/// Pago calculable, caso Mirabilia) y para corregir una fecha ya
/// definida. Sin restricción de `estatus`: aplica sin importar si la
/// cuenta está `pendiente`/`parcial`/`pagada`.
class ActualizarFechaVencimientoCuentaPorCobrarUseCase {
  ActualizarFechaVencimientoCuentaPorCobrarUseCase(this._repository);

  final CuentaPorCobrarRepository _repository;

  Future<ActualizarFechaVencimientoCuentaPorCobrarResultado> ejecutar({
    required String cuentaPorCobrarId,
    required DateTime fechaVencimiento,
    String? motivo,
  }) async {
    final cuenta = await _repository.obtenerPorId(cuentaPorCobrarId);
    if (cuenta == null) {
      return ActualizarFechaVencimientoCuentaPorCobrarNoExiste();
    }

    try {
      final actualizada = await _repository.actualizarFechaVencimiento(
        cuentaPorCobrarId: cuentaPorCobrarId,
        fechaVencimiento: fechaVencimiento,
        motivo: motivo,
      );
      return ActualizarFechaVencimientoCuentaPorCobrarExitoso(actualizada);
    } catch (e) {
      return ActualizarFechaVencimientoCuentaPorCobrarErrorInesperado(e.toString());
    }
  }
}
