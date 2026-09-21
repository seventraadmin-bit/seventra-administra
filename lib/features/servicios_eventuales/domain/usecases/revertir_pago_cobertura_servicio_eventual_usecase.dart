import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/servicio_eventual_table.dart';
import '../repositories/servicio_eventual_repository.dart';

sealed class RevertirPagoCoberturaServicioEventualResultado {}

class RevertirPagoCoberturaServicioEventualExitoso extends RevertirPagoCoberturaServicioEventualResultado {
  RevertirPagoCoberturaServicioEventualExitoso(this.cobertura);
  final ServicioEventualCoberturaData cobertura;
}

class RevertirPagoCoberturaServicioEventualNoExiste
    extends RevertirPagoCoberturaServicioEventualResultado {}

class RevertirPagoCoberturaServicioEventualMotivoRequerido
    extends RevertirPagoCoberturaServicioEventualResultado {}

/// No estaba pagada — no hay nada que revertir. Corta antes de tocar
/// Finanzas, así que revertir dos veces nunca devuelve el dinero dos
/// veces.
class RevertirPagoCoberturaServicioEventualNoPagada
    extends RevertirPagoCoberturaServicioEventualResultado {}

class RevertirPagoCoberturaServicioEventualErrorInesperado
    extends RevertirPagoCoberturaServicioEventualResultado {
  RevertirPagoCoberturaServicioEventualErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Deshace el PAGO, no la cobertura.
///
/// Cancela el Egreso —o revierte el cargo a la tarjeta— exactamente una
/// vez, y devuelve la cobertura a `programada`: el trabajo se siguió
/// comprometiendo y puede volver a pagarse, con otro origen si hace
/// falta. Cancelar el pago **no** es cancelar la cobertura; para eso
/// está `CancelarCoberturaServicioEventualUseCase`, que exige
/// justamente que el pago se haya revertido antes.
class RevertirPagoCoberturaServicioEventualUseCase {
  RevertirPagoCoberturaServicioEventualUseCase(this._repository);

  final ServicioEventualRepository _repository;

  Future<RevertirPagoCoberturaServicioEventualResultado> ejecutar({
    required String coberturaId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return RevertirPagoCoberturaServicioEventualMotivoRequerido();

    final cobertura = await _repository.obtenerCobertura(coberturaId);
    if (cobertura == null) return RevertirPagoCoberturaServicioEventualNoExiste();
    if (cobertura.estatus != EstatusEjecucionServicioEventual.pagada.name) {
      return RevertirPagoCoberturaServicioEventualNoPagada();
    }

    try {
      final revertida = await _repository.revertirPagoCobertura(
        coberturaId: coberturaId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
      return RevertirPagoCoberturaServicioEventualExitoso(revertida);
    } catch (e) {
      return RevertirPagoCoberturaServicioEventualErrorInesperado(e.toString());
    }
  }
}
