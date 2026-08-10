import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/vehiculo_documento_repository.dart';

sealed class AdjuntarArchivoDocumentoVehiculoResultado {}

class AdjuntarArchivoDocumentoVehiculoExitoso extends AdjuntarArchivoDocumentoVehiculoResultado {
  AdjuntarArchivoDocumentoVehiculoExitoso(this.adjunto);
  final AttachmentData adjunto;
}

class AdjuntarArchivoDocumentoVehiculoNoExiste extends AdjuntarArchivoDocumentoVehiculoResultado {}

class AdjuntarArchivoDocumentoVehiculoErrorInesperado extends AdjuntarArchivoDocumentoVehiculoResultado {
  AdjuntarArchivoDocumentoVehiculoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Adjunta el archivo (PDF/imagen) de un `VehiculoDocumento` ya
/// existente (Etapa 8C) — paso opcional y posterior a
/// `RegistrarDocumentoVehiculoUseCase` (mismo patrón de composición
/// segura que `ActualizarFotografiaVehiculoUseCase`). Un documento sin
/// archivo sigue siendo válido si los datos administrativos ya bastan
/// (instrucción explícita de Marlon).
class AdjuntarArchivoDocumentoVehiculoUseCase {
  AdjuntarArchivoDocumentoVehiculoUseCase(this._documentoRepository, this._storage);

  final VehiculoDocumentoRepository _documentoRepository;
  final AttachmentStorage _storage;

  Future<AdjuntarArchivoDocumentoVehiculoResultado> ejecutar({
    required String vehiculoDocumentoId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) async {
    if (await _documentoRepository.obtenerPorId(vehiculoDocumentoId) == null) {
      return AdjuntarArchivoDocumentoVehiculoNoExiste();
    }

    try {
      final guardado = await _storage.guardar(
        ownerId: vehiculoDocumentoId,
        categoria: 'documento',
        sourceFilePath: sourceFilePath,
        originalFileName: originalFileName,
      );
      final adjunto = await _documentoRepository.adjuntarArchivo(
        vehiculoDocumentoId: vehiculoDocumentoId,
        originalFileName: originalFileName,
        storedFileName: guardado.storedFileName,
        path: guardado.path,
        mimeType: mimeType,
        sizeBytes: guardado.sizeBytes,
      );
      return AdjuntarArchivoDocumentoVehiculoExitoso(adjunto);
    } catch (e) {
      return AdjuntarArchivoDocumentoVehiculoErrorInesperado(e.toString());
    }
  }
}
