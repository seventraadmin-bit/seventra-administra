import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/ingreso_table.dart';

import '../repositories/ingreso_repository.dart';

sealed class CancelarIngresoResultado {}

class CancelarIngresoExitoso extends CancelarIngresoResultado {
  CancelarIngresoExitoso(this.ingreso);
  final IngresoData ingreso;
}

class CancelarIngresoNoExiste extends CancelarIngresoResultado {}

class CancelarIngresoYaCancelado extends CancelarIngresoResultado {}

/// Un Ingreso automático (`pagoId != null`) se cancela junto con su
/// Pago (`PagoRepositoryImpl.cancelar`), nunca por separado — cancelar
/// solo el Ingreso dejaría un Pago "recibido" sin su reconocimiento
/// contable, una inconsistencia que este caso de uso previene.
class CancelarIngresoPagoAutomatico extends CancelarIngresoResultado {}

class CancelarIngresoErrorInesperado extends CancelarIngresoResultado {
  CancelarIngresoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cancela un Ingreso manual (Etapa 4K.1). Requiere `motivo`.
class CancelarIngresoUseCase {
  CancelarIngresoUseCase(this._repository);

  final IngresoRepository _repository;

  Future<CancelarIngresoResultado> ejecutar({
    required String ingresoId,
    required String motivo,
    String? actor,
  }) async {
    final ingreso = await _repository.obtenerPorId(ingresoId);
    if (ingreso == null) {
      return CancelarIngresoNoExiste();
    }
    if (EstatusIngreso.values.byName(ingreso.estatus) == EstatusIngreso.cancelado) {
      return CancelarIngresoYaCancelado();
    }
    if (ingreso.pagoId != null) {
      return CancelarIngresoPagoAutomatico();
    }

    try {
      final actualizado = await _repository.cancelar(ingresoId: ingresoId, motivo: motivo, actor: actor);
      return CancelarIngresoExitoso(actualizado);
    } catch (e) {
      return CancelarIngresoErrorInesperado(e.toString());
    }
  }
}
