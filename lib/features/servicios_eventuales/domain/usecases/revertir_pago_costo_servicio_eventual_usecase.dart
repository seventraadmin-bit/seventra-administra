import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/servicio_eventual_table.dart';
import '../repositories/servicio_eventual_repository.dart';

sealed class RevertirPagoCostoServicioEventualResultado {}

class RevertirPagoCostoServicioEventualExitoso extends RevertirPagoCostoServicioEventualResultado {
  RevertirPagoCostoServicioEventualExitoso(this.costo);
  final ServicioEventualCostoData costo;
}

class RevertirPagoCostoServicioEventualNoExiste extends RevertirPagoCostoServicioEventualResultado {}

class RevertirPagoCostoServicioEventualMotivoRequerido
    extends RevertirPagoCostoServicioEventualResultado {}

class RevertirPagoCostoServicioEventualNoPagado extends RevertirPagoCostoServicioEventualResultado {}

class RevertirPagoCostoServicioEventualErrorInesperado
    extends RevertirPagoCostoServicioEventualResultado {
  RevertirPagoCostoServicioEventualErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Deshace el pago de un costo adicional sin cancelarlo: vuelve a
/// `programado` y puede pagarse otra vez. Misma regla que en una
/// cobertura.
class RevertirPagoCostoServicioEventualUseCase {
  RevertirPagoCostoServicioEventualUseCase(this._repository);

  final ServicioEventualRepository _repository;

  Future<RevertirPagoCostoServicioEventualResultado> ejecutar({
    required String costoId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return RevertirPagoCostoServicioEventualMotivoRequerido();

    final costo = await _repository.obtenerCosto(costoId);
    if (costo == null) return RevertirPagoCostoServicioEventualNoExiste();
    if (costo.estatus != EstatusEjecucionServicioEventual.pagada.name) {
      return RevertirPagoCostoServicioEventualNoPagado();
    }

    try {
      final revertido = await _repository.revertirPagoCosto(
        costoId: costoId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
      return RevertirPagoCostoServicioEventualExitoso(revertido);
    } catch (e) {
      return RevertirPagoCostoServicioEventualErrorInesperado(e.toString());
    }
  }
}
