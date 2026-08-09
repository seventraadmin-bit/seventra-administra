import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/egreso_table.dart';

import '../repositories/egreso_repository.dart';

sealed class CancelarEgresoResultado {}

class CancelarEgresoExitoso extends CancelarEgresoResultado {
  CancelarEgresoExitoso(this.egreso);
  final EgresoData egreso;
}

class CancelarEgresoNoExiste extends CancelarEgresoResultado {}

class CancelarEgresoYaCancelado extends CancelarEgresoResultado {}

class CancelarEgresoErrorInesperado extends CancelarEgresoResultado {
  CancelarEgresoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cancela un Egreso (Etapa 4K.1). Requiere `motivo`. A diferencia de
/// `CancelarIngresoUseCase`, no existe una fuente automática que
/// cancelar en cascada — todo Egreso es de captura manual.
class CancelarEgresoUseCase {
  CancelarEgresoUseCase(this._repository);

  final EgresoRepository _repository;

  Future<CancelarEgresoResultado> ejecutar({
    required String egresoId,
    required String motivo,
    String? actor,
  }) async {
    final egreso = await _repository.obtenerPorId(egresoId);
    if (egreso == null) {
      return CancelarEgresoNoExiste();
    }
    if (EstatusEgreso.values.byName(egreso.estatus) == EstatusEgreso.cancelado) {
      return CancelarEgresoYaCancelado();
    }

    try {
      final actualizado = await _repository.cancelar(egresoId: egresoId, motivo: motivo, actor: actor);
      return CancelarEgresoExitoso(actualizado);
    } catch (e) {
      return CancelarEgresoErrorInesperado(e.toString());
    }
  }
}
