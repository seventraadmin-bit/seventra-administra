import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/pago_nomina_repository.dart';

sealed class AdjuntarComprobantePagoNominaResultado {}

class AdjuntarComprobantePagoNominaExitoso extends AdjuntarComprobantePagoNominaResultado {
  AdjuntarComprobantePagoNominaExitoso(this.adjunto);
  final AttachmentData adjunto;
}

class AdjuntarComprobantePagoNominaNoExiste extends AdjuntarComprobantePagoNominaResultado {}

class AdjuntarComprobantePagoNominaErrorInesperado extends AdjuntarComprobantePagoNominaResultado {
  AdjuntarComprobantePagoNominaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Adjunta un comprobante a un `PagoNomina` (Etapa 6D) — mismo
/// mecanismo que cualquier otro adjunto (`Attachment`), sin
/// restricción de tipo de archivo, mismo criterio que
/// `AdjuntarComprobanteEgresoUseCase`.
class AdjuntarComprobantePagoNominaUseCase {
  AdjuntarComprobantePagoNominaUseCase(this._repository, this._storage);

  final PagoNominaRepository _repository;
  final AttachmentStorage _storage;

  Future<AdjuntarComprobantePagoNominaResultado> ejecutar({
    required String pagoNominaId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) async {
    final pagoNomina = await _repository.obtenerPorId(pagoNominaId);
    if (pagoNomina == null) {
      return AdjuntarComprobantePagoNominaNoExiste();
    }

    try {
      final guardado = await _storage.guardar(
        ownerId: pagoNominaId,
        categoria: 'comprobante',
        sourceFilePath: sourceFilePath,
        originalFileName: originalFileName,
      );
      final adjunto = await _repository.adjuntarComprobante(
        pagoNominaId: pagoNominaId,
        originalFileName: originalFileName,
        storedFileName: guardado.storedFileName,
        path: guardado.path,
        mimeType: mimeType,
        sizeBytes: guardado.sizeBytes,
      );
      return AdjuntarComprobantePagoNominaExitoso(adjunto);
    } catch (e) {
      return AdjuntarComprobantePagoNominaErrorInesperado(e.toString());
    }
  }
}
