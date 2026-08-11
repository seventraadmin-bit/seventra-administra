import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/compra_repository.dart';

sealed class AdjuntarComprobanteCompraResultado {}

class AdjuntarComprobanteCompraExitoso extends AdjuntarComprobanteCompraResultado {
  AdjuntarComprobanteCompraExitoso(this.adjunto);
  final AttachmentData adjunto;
}

class AdjuntarComprobanteCompraNoExiste extends AdjuntarComprobanteCompraResultado {}

class AdjuntarComprobanteCompraErrorInesperado extends AdjuntarComprobanteCompraResultado {
  AdjuntarComprobanteCompraErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Adjunta el comprobante/factura PDF de una Compra ya registrada
/// (Etapa 10) — paso opcional y posterior a `RegistrarCompraUseCase`,
/// mismo patrón de composición segura que
/// `AdjuntarComprobanteRecargaLineaTelefonicaUseCase`. Una Compra sin
/// comprobante sigue siendo válida — nunca obligatorio.
class AdjuntarComprobanteCompraUseCase {
  AdjuntarComprobanteCompraUseCase(this._compraRepository, this._storage);

  final CompraRepository _compraRepository;
  final AttachmentStorage _storage;

  Future<AdjuntarComprobanteCompraResultado> ejecutar({
    required String compraId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) async {
    if (await _compraRepository.obtenerPorId(compraId) == null) {
      return AdjuntarComprobanteCompraNoExiste();
    }

    try {
      final guardado = await _storage.guardar(
        ownerId: compraId,
        categoria: 'compra',
        sourceFilePath: sourceFilePath,
        originalFileName: originalFileName,
      );
      final adjunto = await _compraRepository.adjuntarComprobante(
        compraId: compraId,
        originalFileName: originalFileName,
        storedFileName: guardado.storedFileName,
        path: guardado.path,
        mimeType: mimeType,
        sizeBytes: guardado.sizeBytes,
      );
      return AdjuntarComprobanteCompraExitoso(adjunto);
    } catch (e) {
      return AdjuntarComprobanteCompraErrorInesperado(e.toString());
    }
  }
}
