import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/tiempo_extra_repository.dart';

sealed class CancelarTiempoExtraResultado {}

class CancelarTiempoExtraExitoso extends CancelarTiempoExtraResultado {
  CancelarTiempoExtraExitoso(this.tiempoExtra);
  final TiempoExtraData tiempoExtra;
}

class CancelarTiempoExtraNoExiste extends CancelarTiempoExtraResultado {}

class CancelarTiempoExtraYaCancelado extends CancelarTiempoExtraResultado {}

class CancelarTiempoExtraErrorInesperado extends CancelarTiempoExtraResultado {
  CancelarTiempoExtraErrorInesperado(this.mensaje);
  final String mensaje;
}

class CancelarTiempoExtraUseCase {
  CancelarTiempoExtraUseCase(this._repository);

  final TiempoExtraRepository _repository;

  Future<CancelarTiempoExtraResultado> ejecutar({
    required String tiempoExtraId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final actual = await _repository.obtenerPorId(tiempoExtraId);
    if (actual == null) return CancelarTiempoExtraNoExiste();
    if (actual.estatus == 'cancelado') return CancelarTiempoExtraYaCancelado();

    try {
      final cancelado = await _repository.cancelar(
        tiempoExtraId: tiempoExtraId,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return CancelarTiempoExtraExitoso(cancelado);
    } catch (e) {
      return CancelarTiempoExtraErrorInesperado(e.toString());
    }
  }
}
