import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/inventario_repository.dart';

sealed class AdjuntarComprobanteMovimientoResultado {}

class AdjuntarComprobanteMovimientoExitoso extends AdjuntarComprobanteMovimientoResultado {
  AdjuntarComprobanteMovimientoExitoso(this.adjunto);
  final AttachmentData adjunto;
}

class AdjuntarComprobanteMovimientoErrorInesperado extends AdjuntarComprobanteMovimientoResultado {
  AdjuntarComprobanteMovimientoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Adjunta un comprobante a un `MovimientoInventario` (Etapa 7A,
/// típicamente una entrada) — mismo mecanismo que cualquier otro
/// adjunto (`Attachment`), sin restricción de tipo de archivo.
class AdjuntarComprobanteMovimientoUseCase {
  AdjuntarComprobanteMovimientoUseCase(this._repository, this._storage);

  final InventarioRepository _repository;
  final AttachmentStorage _storage;

  Future<AdjuntarComprobanteMovimientoResultado> ejecutar({
    required String movimientoInventarioId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) async {
    try {
      final guardado = await _storage.guardar(
        ownerId: movimientoInventarioId,
        categoria: 'comprobante',
        sourceFilePath: sourceFilePath,
        originalFileName: originalFileName,
      );
      final adjunto = await _repository.adjuntarComprobante(
        movimientoInventarioId: movimientoInventarioId,
        originalFileName: originalFileName,
        storedFileName: guardado.storedFileName,
        path: guardado.path,
        mimeType: mimeType,
        sizeBytes: guardado.sizeBytes,
      );
      return AdjuntarComprobanteMovimientoExitoso(adjunto);
    } catch (e) {
      return AdjuntarComprobanteMovimientoErrorInesperado(e.toString());
    }
  }
}
