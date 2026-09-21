import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/servicio_eventual_table.dart';
import '../repositories/servicio_eventual_repository.dart';

sealed class FinalizarServicioEventualResultado {}

class FinalizarServicioEventualExitoso extends FinalizarServicioEventualResultado {
  FinalizarServicioEventualExitoso(this.servicioEventual);
  final ServicioEventualData servicioEventual;
}

class FinalizarServicioEventualNoExiste extends FinalizarServicioEventualResultado {}

class FinalizarServicioEventualCancelado extends FinalizarServicioEventualResultado {}

class FinalizarServicioEventualYaFinalizado extends FinalizarServicioEventualResultado {}

class FinalizarServicioEventualErrorInesperado extends FinalizarServicioEventualResultado {
  FinalizarServicioEventualErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Marca el evento como ocurrido.
///
/// **Finalizar no cobra nada y no paga nada.** No cierra las coberturas
/// pendientes de pago —pagar al personal después del evento es lo
/// normal— y en la Rebanada 1 tampoco genera Cuenta por cobrar: será
/// la Rebanada 2 la que enganche aquí la cobranza eventual.
class FinalizarServicioEventualUseCase {
  FinalizarServicioEventualUseCase(this._repository);

  final ServicioEventualRepository _repository;

  Future<FinalizarServicioEventualResultado> ejecutar({
    required String servicioEventualId,
    String? actorUsuarioId,
  }) async {
    final actual = await _repository.obtenerPorId(servicioEventualId);
    if (actual == null) return FinalizarServicioEventualNoExiste();
    if (actual.estatus == EstatusServicioEventual.cancelado.name) {
      return FinalizarServicioEventualCancelado();
    }
    if (actual.estatus == EstatusServicioEventual.finalizado.name) {
      return FinalizarServicioEventualYaFinalizado();
    }

    try {
      final eventual = await _repository.cambiarEstatus(
        servicioEventualId: servicioEventualId,
        estatus: EstatusServicioEventual.finalizado,
        actorUsuarioId: actorUsuarioId,
      );
      return FinalizarServicioEventualExitoso(eventual);
    } catch (e) {
      return FinalizarServicioEventualErrorInesperado(e.toString());
    }
  }
}
