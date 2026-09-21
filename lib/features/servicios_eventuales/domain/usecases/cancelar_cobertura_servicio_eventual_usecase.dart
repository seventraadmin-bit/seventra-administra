import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/servicio_eventual_table.dart';
import '../repositories/servicio_eventual_repository.dart';

sealed class CancelarCoberturaServicioEventualResultado {}

class CancelarCoberturaServicioEventualExitoso extends CancelarCoberturaServicioEventualResultado {
  CancelarCoberturaServicioEventualExitoso(this.cobertura);
  final ServicioEventualCoberturaData cobertura;
}

class CancelarCoberturaServicioEventualNoExiste extends CancelarCoberturaServicioEventualResultado {}

class CancelarCoberturaServicioEventualMotivoRequerido extends CancelarCoberturaServicioEventualResultado {}

class CancelarCoberturaServicioEventualYaCancelada extends CancelarCoberturaServicioEventualResultado {}

/// Está pagada: cancelarla dejaría un Egreso o un cargo a tarjeta sin
/// nada que lo justifique. Se revierte el pago primero — y entonces la
/// cobertura, ya en `programada`, sí puede cancelarse.
class CancelarCoberturaServicioEventualPagada extends CancelarCoberturaServicioEventualResultado {}

class CancelarCoberturaServicioEventualErrorInesperado extends CancelarCoberturaServicioEventualResultado {
  CancelarCoberturaServicioEventualErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cancela una cobertura que no ocurrió. Nunca la borra: el compromiso
/// existió y su rastro se conserva con el motivo.
class CancelarCoberturaServicioEventualUseCase {
  CancelarCoberturaServicioEventualUseCase(this._repository);

  final ServicioEventualRepository _repository;

  Future<CancelarCoberturaServicioEventualResultado> ejecutar({
    required String coberturaId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return CancelarCoberturaServicioEventualMotivoRequerido();

    final actual = await _repository.obtenerCobertura(coberturaId);
    if (actual == null) return CancelarCoberturaServicioEventualNoExiste();
    if (actual.estatus == EstatusEjecucionServicioEventual.cancelada.name) {
      return CancelarCoberturaServicioEventualYaCancelada();
    }
    if (actual.estatus == EstatusEjecucionServicioEventual.pagada.name) {
      return CancelarCoberturaServicioEventualPagada();
    }

    try {
      final cobertura = await _repository.cancelarCobertura(
        coberturaId: coberturaId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
      return CancelarCoberturaServicioEventualExitoso(cobertura);
    } catch (e) {
      return CancelarCoberturaServicioEventualErrorInesperado(e.toString());
    }
  }
}
