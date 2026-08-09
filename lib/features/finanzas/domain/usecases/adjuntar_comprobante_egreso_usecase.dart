import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/egreso_repository.dart';

sealed class AdjuntarComprobanteEgresoResultado {}

class AdjuntarComprobanteEgresoExitoso extends AdjuntarComprobanteEgresoResultado {
  AdjuntarComprobanteEgresoExitoso(this.adjunto);
  final AttachmentData adjunto;
}

class AdjuntarComprobanteEgresoNoExiste extends AdjuntarComprobanteEgresoResultado {}

class AdjuntarComprobanteEgresoErrorInesperado extends AdjuntarComprobanteEgresoResultado {
  AdjuntarComprobanteEgresoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Adjunta un comprobante a un Egreso (Etapa 4K.1) — mismo mecanismo
/// que cualquier otro adjunto (`Attachment`), sin restricción de tipo
/// de archivo.
class AdjuntarComprobanteEgresoUseCase {
  AdjuntarComprobanteEgresoUseCase(this._repository, this._storage);

  final EgresoRepository _repository;
  final AttachmentStorage _storage;

  Future<AdjuntarComprobanteEgresoResultado> ejecutar({
    required String egresoId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) async {
    final egreso = await _repository.obtenerPorId(egresoId);
    if (egreso == null) {
      return AdjuntarComprobanteEgresoNoExiste();
    }

    try {
      final guardado = await _storage.guardar(
        ownerId: egresoId,
        categoria: 'comprobante',
        sourceFilePath: sourceFilePath,
        originalFileName: originalFileName,
      );
      final adjunto = await _repository.adjuntarComprobante(
        egresoId: egresoId,
        originalFileName: originalFileName,
        storedFileName: guardado.storedFileName,
        path: guardado.path,
        mimeType: mimeType,
        sizeBytes: guardado.sizeBytes,
      );
      return AdjuntarComprobanteEgresoExitoso(adjunto);
    } catch (e) {
      return AdjuntarComprobanteEgresoErrorInesperado(e.toString());
    }
  }
}
