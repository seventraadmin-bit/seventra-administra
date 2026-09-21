import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/servicio_eventual_table.dart';
import '../repositories/servicio_eventual_repository.dart';

sealed class CancelarCostoServicioEventualResultado {}

class CancelarCostoServicioEventualExitoso extends CancelarCostoServicioEventualResultado {
  CancelarCostoServicioEventualExitoso(this.costo);
  final ServicioEventualCostoData costo;
}

class CancelarCostoServicioEventualNoExiste extends CancelarCostoServicioEventualResultado {}

class CancelarCostoServicioEventualMotivoRequerido extends CancelarCostoServicioEventualResultado {}

class CancelarCostoServicioEventualYaCancelado extends CancelarCostoServicioEventualResultado {}

/// Está pagado: se revierte el pago primero, igual que en una
/// cobertura.
class CancelarCostoServicioEventualPagado extends CancelarCostoServicioEventualResultado {}

class CancelarCostoServicioEventualErrorInesperado extends CancelarCostoServicioEventualResultado {
  CancelarCostoServicioEventualErrorInesperado(this.mensaje);
  final String mensaje;
}

class CancelarCostoServicioEventualUseCase {
  CancelarCostoServicioEventualUseCase(this._repository);

  final ServicioEventualRepository _repository;

  Future<CancelarCostoServicioEventualResultado> ejecutar({
    required String costoId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return CancelarCostoServicioEventualMotivoRequerido();

    final actual = await _repository.obtenerCosto(costoId);
    if (actual == null) return CancelarCostoServicioEventualNoExiste();
    if (actual.estatus == EstatusEjecucionServicioEventual.cancelada.name) {
      return CancelarCostoServicioEventualYaCancelado();
    }
    if (actual.estatus == EstatusEjecucionServicioEventual.pagada.name) {
      return CancelarCostoServicioEventualPagado();
    }

    try {
      final costo = await _repository.cancelarCosto(
        costoId: costoId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
      return CancelarCostoServicioEventualExitoso(costo);
    } catch (e) {
      return CancelarCostoServicioEventualErrorInesperado(e.toString());
    }
  }
}
