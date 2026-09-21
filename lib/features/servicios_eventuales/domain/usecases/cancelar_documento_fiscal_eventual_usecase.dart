import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/servicio_eventual_documento_fiscal_table.dart';
import '../repositories/servicio_eventual_documento_fiscal_repository.dart';

sealed class CancelarDocumentoFiscalEventualResultado {}

class CancelarDocumentoFiscalEventualExitoso extends CancelarDocumentoFiscalEventualResultado {
  CancelarDocumentoFiscalEventualExitoso(this.documento);
  final ServicioEventualDocumentoFiscalData documento;
}

class CancelarDocumentoFiscalEventualNoExiste extends CancelarDocumentoFiscalEventualResultado {}

class CancelarDocumentoFiscalEventualMotivoRequerido extends CancelarDocumentoFiscalEventualResultado {}

class CancelarDocumentoFiscalEventualYaCancelado extends CancelarDocumentoFiscalEventualResultado {}

class CancelarDocumentoFiscalEventualErrorInesperado extends CancelarDocumentoFiscalEventualResultado {
  CancelarDocumentoFiscalEventualErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cancela el CFDI del eventual conservándolo en el histórico.
///
/// **Nunca cancela el Pago ni la Cuenta por cobrar**, y nunca devuelve
/// dinero: que un documento fiscal se haya cancelado no borra la venta
/// ni el cobro. Lo único que cambia en la cobranza es que la Cuenta
/// deja de citar un folio muerto; el acuerdo PUE/PPD y la obligación de
/// Complemento se conservan hasta que el sustituto los reemplace.
///
/// Tras cancelar, el índice único parcial vuelve a permitir registrar
/// un documento vigente: ése es exactamente el mecanismo de sustitución
/// que ya se fijó para el Complemento en la schemaVersion 79.
class CancelarDocumentoFiscalEventualUseCase {
  CancelarDocumentoFiscalEventualUseCase(this._repository);

  final ServicioEventualDocumentoFiscalRepository _repository;

  Future<CancelarDocumentoFiscalEventualResultado> ejecutar({
    required String documentoId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return CancelarDocumentoFiscalEventualMotivoRequerido();

    final actual = await _repository.obtenerPorId(documentoId);
    if (actual == null) return CancelarDocumentoFiscalEventualNoExiste();
    if (actual.estatus == EstatusDocumentoFiscalEventual.cancelado.name) {
      return CancelarDocumentoFiscalEventualYaCancelado();
    }

    try {
      final documento = await _repository.cancelar(
        documentoId: documentoId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
      return CancelarDocumentoFiscalEventualExitoso(documento);
    } catch (e) {
      return CancelarDocumentoFiscalEventualErrorInesperado(e.toString());
    }
  }
}
