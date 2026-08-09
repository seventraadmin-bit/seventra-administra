import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/pago_repository.dart';

sealed class AdjuntarComprobantePagoResultado {}

class AdjuntarComprobantePagoExitoso extends AdjuntarComprobantePagoResultado {
  AdjuntarComprobantePagoExitoso(this.adjunto);
  final AttachmentData adjunto;
}

class AdjuntarComprobantePagoNoExiste extends AdjuntarComprobantePagoResultado {}

class AdjuntarComprobantePagoErrorInesperado extends AdjuntarComprobantePagoResultado {
  AdjuntarComprobantePagoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Adjunta un comprobante de pago (Etapa 4J.2, Resolución 4 de
/// Marlon): mismo mecanismo que cualquier otro adjunto (`Attachment`),
/// sin campo dedicado dentro de `Pago` y sin restricción de tipo de
/// archivo (PDF/XML/JPG/PNG/etc.) — a diferencia de los adjuntos de
/// `DocumentoPorEmitir`, aquí no hay categorías que validar entre sí.
class AdjuntarComprobantePagoUseCase {
  AdjuntarComprobantePagoUseCase(this._repository, this._storage);

  final PagoRepository _repository;
  final AttachmentStorage _storage;

  Future<AdjuntarComprobantePagoResultado> ejecutar({
    required String pagoId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) async {
    final pago = await _repository.obtenerPorId(pagoId);
    if (pago == null) {
      return AdjuntarComprobantePagoNoExiste();
    }

    try {
      final guardado = await _storage.guardar(
        ownerId: pagoId,
        categoria: 'comprobante',
        sourceFilePath: sourceFilePath,
        originalFileName: originalFileName,
      );
      final adjunto = await _repository.adjuntarComprobante(
        pagoId: pagoId,
        originalFileName: originalFileName,
        storedFileName: guardado.storedFileName,
        path: guardado.path,
        mimeType: mimeType,
        sizeBytes: guardado.sizeBytes,
      );
      return AdjuntarComprobantePagoExitoso(adjunto);
    } catch (e) {
      return AdjuntarComprobantePagoErrorInesperado(e.toString());
    }
  }
}
