import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/egreso_table.dart';

import '../repositories/egreso_repository.dart';

sealed class CorregirEgresoResultado {}

class CorregirEgresoExitoso extends CorregirEgresoResultado {
  CorregirEgresoExitoso(this.egreso);
  final EgresoData egreso;
}

class CorregirEgresoNoExiste extends CorregirEgresoResultado {}

class CorregirEgresoCancelado extends CorregirEgresoResultado {}

class CorregirEgresoErrorInesperado extends CorregirEgresoResultado {
  CorregirEgresoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige metadatos administrativos de un Egreso — nunca `monto`
/// (Etapa 4K.1, mismo criterio que `Ingreso`/`Pago`). Requiere `motivo`.
class CorregirEgresoUseCase {
  CorregirEgresoUseCase(this._repository);

  final EgresoRepository _repository;

  Future<CorregirEgresoResultado> ejecutar({
    required String egresoId,
    DateTime? fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    String? formaPago,
    String? beneficiario,
    String? concepto,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final egreso = await _repository.obtenerPorId(egresoId);
    if (egreso == null) {
      return CorregirEgresoNoExiste();
    }
    if (EstatusEgreso.values.byName(egreso.estatus) == EstatusEgreso.cancelado) {
      return CorregirEgresoCancelado();
    }

    try {
      final actualizado = await _repository.corregir(
        egresoId: egresoId,
        fecha: fecha,
        categoriaFinancieraId: categoriaFinancieraId,
        servicioId: servicioId,
        sucursalId: sucursalId,
        areaId: areaId,
        cuentaCaja: cuentaCaja,
        formaPago: formaPago,
        beneficiario: beneficiario,
        concepto: concepto,
        observaciones: observaciones,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return CorregirEgresoExitoso(actualizado);
    } catch (e) {
      return CorregirEgresoErrorInesperado(e.toString());
    }
  }
}
