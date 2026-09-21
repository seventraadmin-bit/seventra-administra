import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/servicio_eventual_table.dart';
import '../repositories/servicio_eventual_repository.dart';

sealed class CorregirCostoServicioEventualResultado {}

class CorregirCostoServicioEventualExitoso extends CorregirCostoServicioEventualResultado {
  CorregirCostoServicioEventualExitoso(this.costo);
  final ServicioEventualCostoData costo;
}

class CorregirCostoServicioEventualNoExiste extends CorregirCostoServicioEventualResultado {}

class CorregirCostoServicioEventualMotivoRequerido extends CorregirCostoServicioEventualResultado {}

class CorregirCostoServicioEventualConceptoRequerido extends CorregirCostoServicioEventualResultado {}

class CorregirCostoServicioEventualMontoInvalido extends CorregirCostoServicioEventualResultado {}

class CorregirCostoServicioEventualCancelado extends CorregirCostoServicioEventualResultado {}

/// Mismo motivo que en la cobertura: el monto corregido dejaría de
/// coincidir con el Egreso o el cargo ya emitido.
class CorregirCostoServicioEventualPagado extends CorregirCostoServicioEventualResultado {}

class CorregirCostoServicioEventualErrorInesperado extends CorregirCostoServicioEventualResultado {
  CorregirCostoServicioEventualErrorInesperado(this.mensaje);
  final String mensaje;
}

class CorregirCostoServicioEventualUseCase {
  CorregirCostoServicioEventualUseCase(this._repository);

  final ServicioEventualRepository _repository;

  Future<CorregirCostoServicioEventualResultado> ejecutar({
    required String costoId,
    String? concepto,
    int? monto,
    DateTime? fecha,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return CorregirCostoServicioEventualMotivoRequerido();

    final actual = await _repository.obtenerCosto(costoId);
    if (actual == null) return CorregirCostoServicioEventualNoExiste();
    if (actual.estatus == EstatusEjecucionServicioEventual.cancelada.name) {
      return CorregirCostoServicioEventualCancelado();
    }
    if (actual.estatus == EstatusEjecucionServicioEventual.pagada.name) {
      return CorregirCostoServicioEventualPagado();
    }

    final conceptoLimpio = concepto?.trim();
    if (conceptoLimpio != null && conceptoLimpio.isEmpty) {
      return CorregirCostoServicioEventualConceptoRequerido();
    }
    if (monto != null && monto <= 0) return CorregirCostoServicioEventualMontoInvalido();

    try {
      final costo = await _repository.corregirCosto(
        costoId: costoId,
        concepto: conceptoLimpio,
        monto: monto,
        fecha: fecha,
        observaciones: observaciones?.trim().isEmpty ?? true ? null : observaciones!.trim(),
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
      return CorregirCostoServicioEventualExitoso(costo);
    } catch (e) {
      return CorregirCostoServicioEventualErrorInesperado(e.toString());
    }
  }
}
