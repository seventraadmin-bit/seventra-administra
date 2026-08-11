import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/recarga_linea_telefonica_repository.dart';

sealed class AdjuntarComprobanteRecargaLineaTelefonicaResultado {}

class AdjuntarComprobanteRecargaLineaTelefonicaExitoso extends AdjuntarComprobanteRecargaLineaTelefonicaResultado {
  AdjuntarComprobanteRecargaLineaTelefonicaExitoso(this.adjunto);
  final AttachmentData adjunto;
}

class AdjuntarComprobanteRecargaLineaTelefonicaNoExiste extends AdjuntarComprobanteRecargaLineaTelefonicaResultado {}

class AdjuntarComprobanteRecargaLineaTelefonicaErrorInesperado extends AdjuntarComprobanteRecargaLineaTelefonicaResultado {
  AdjuntarComprobanteRecargaLineaTelefonicaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Adjunta el comprobante de una recarga ya registrada (Etapa 9C) —
/// paso opcional y posterior a
/// `RegistrarRecargaLineaTelefonicaUseCase`, mismo patrón de
/// composición segura que
/// `AdjuntarComprobanteMantenimientoVehiculoUseCase` (8D). Una recarga
/// sin comprobante sigue siendo válida — nunca obligatorio.
class AdjuntarComprobanteRecargaLineaTelefonicaUseCase {
  AdjuntarComprobanteRecargaLineaTelefonicaUseCase(this._recargaRepository, this._storage);

  final RecargaLineaTelefonicaRepository _recargaRepository;
  final AttachmentStorage _storage;

  Future<AdjuntarComprobanteRecargaLineaTelefonicaResultado> ejecutar({
    required String recargaLineaTelefonicaId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) async {
    if (await _recargaRepository.obtenerPorId(recargaLineaTelefonicaId) == null) {
      return AdjuntarComprobanteRecargaLineaTelefonicaNoExiste();
    }

    try {
      final guardado = await _storage.guardar(
        ownerId: recargaLineaTelefonicaId,
        categoria: 'recarga_linea_telefonica',
        sourceFilePath: sourceFilePath,
        originalFileName: originalFileName,
      );
      final adjunto = await _recargaRepository.adjuntarComprobante(
        recargaLineaTelefonicaId: recargaLineaTelefonicaId,
        originalFileName: originalFileName,
        storedFileName: guardado.storedFileName,
        path: guardado.path,
        mimeType: mimeType,
        sizeBytes: guardado.sizeBytes,
      );
      return AdjuntarComprobanteRecargaLineaTelefonicaExitoso(adjunto);
    } catch (e) {
      return AdjuntarComprobanteRecargaLineaTelefonicaErrorInesperado(e.toString());
    }
  }
}
