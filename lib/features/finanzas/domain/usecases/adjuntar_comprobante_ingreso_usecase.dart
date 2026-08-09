import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/ingreso_repository.dart';

sealed class AdjuntarComprobanteIngresoResultado {}

class AdjuntarComprobanteIngresoExitoso extends AdjuntarComprobanteIngresoResultado {
  AdjuntarComprobanteIngresoExitoso(this.adjunto);
  final AttachmentData adjunto;
}

class AdjuntarComprobanteIngresoNoExiste extends AdjuntarComprobanteIngresoResultado {}

class AdjuntarComprobanteIngresoErrorInesperado extends AdjuntarComprobanteIngresoResultado {
  AdjuntarComprobanteIngresoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Adjunta un comprobante a un Ingreso (Etapa 4K.1) — mismo mecanismo
/// que cualquier otro adjunto (`Attachment`), sin restricción de tipo
/// de archivo.
class AdjuntarComprobanteIngresoUseCase {
  AdjuntarComprobanteIngresoUseCase(this._repository, this._storage);

  final IngresoRepository _repository;
  final AttachmentStorage _storage;

  Future<AdjuntarComprobanteIngresoResultado> ejecutar({
    required String ingresoId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) async {
    final ingreso = await _repository.obtenerPorId(ingresoId);
    if (ingreso == null) {
      return AdjuntarComprobanteIngresoNoExiste();
    }

    try {
      final guardado = await _storage.guardar(
        ownerId: ingresoId,
        categoria: 'comprobante',
        sourceFilePath: sourceFilePath,
        originalFileName: originalFileName,
      );
      final adjunto = await _repository.adjuntarComprobante(
        ingresoId: ingresoId,
        originalFileName: originalFileName,
        storedFileName: guardado.storedFileName,
        path: guardado.path,
        mimeType: mimeType,
        sizeBytes: guardado.sizeBytes,
      );
      return AdjuntarComprobanteIngresoExitoso(adjunto);
    } catch (e) {
      return AdjuntarComprobanteIngresoErrorInesperado(e.toString());
    }
  }
}
