import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/ingreso_table.dart';

import '../repositories/ingreso_repository.dart';

sealed class CorregirIngresoResultado {}

class CorregirIngresoExitoso extends CorregirIngresoResultado {
  CorregirIngresoExitoso(this.ingreso);
  final IngresoData ingreso;
}

class CorregirIngresoNoExiste extends CorregirIngresoResultado {}

class CorregirIngresoCancelado extends CorregirIngresoResultado {}

class CorregirIngresoErrorInesperado extends CorregirIngresoResultado {
  CorregirIngresoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige metadatos administrativos de un Ingreso — nunca `monto`
/// (Etapa 4K.1, mismo criterio que `Pago`). Requiere `motivo`.
class CorregirIngresoUseCase {
  CorregirIngresoUseCase(this._repository);

  final IngresoRepository _repository;

  Future<CorregirIngresoResultado> ejecutar({
    required String ingresoId,
    DateTime? fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    String? formaPago,
    String? concepto,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final ingreso = await _repository.obtenerPorId(ingresoId);
    if (ingreso == null) {
      return CorregirIngresoNoExiste();
    }
    if (EstatusIngreso.values.byName(ingreso.estatus) == EstatusIngreso.cancelado) {
      return CorregirIngresoCancelado();
    }

    try {
      final actualizado = await _repository.corregir(
        ingresoId: ingresoId,
        fecha: fecha,
        categoriaFinancieraId: categoriaFinancieraId,
        servicioId: servicioId,
        sucursalId: sucursalId,
        areaId: areaId,
        cuentaCaja: cuentaCaja,
        formaPago: formaPago,
        concepto: concepto,
        observaciones: observaciones,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return CorregirIngresoExitoso(actualizado);
    } catch (e) {
      return CorregirIngresoErrorInesperado(e.toString());
    }
  }
}
