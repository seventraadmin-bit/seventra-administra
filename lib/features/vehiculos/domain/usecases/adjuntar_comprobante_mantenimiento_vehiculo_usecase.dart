import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/vehiculo_mantenimiento_repository.dart';

sealed class AdjuntarComprobanteMantenimientoVehiculoResultado {}

class AdjuntarComprobanteMantenimientoVehiculoExitoso extends AdjuntarComprobanteMantenimientoVehiculoResultado {
  AdjuntarComprobanteMantenimientoVehiculoExitoso(this.adjunto);
  final AttachmentData adjunto;
}

class AdjuntarComprobanteMantenimientoVehiculoNoExiste extends AdjuntarComprobanteMantenimientoVehiculoResultado {}

class AdjuntarComprobanteMantenimientoVehiculoErrorInesperado extends AdjuntarComprobanteMantenimientoVehiculoResultado {
  AdjuntarComprobanteMantenimientoVehiculoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Adjunta el comprobante (o evidencia) de un `VehiculoMantenimiento` ya
/// existente (Etapa 8D) — paso opcional y posterior a
/// `RegistrarMantenimientoVehiculoUseCase`, mismo patrón de composición
/// segura que `AdjuntarArchivoDocumentoVehiculoUseCase` (8C). Un
/// registro sin comprobante sigue siendo válido.
class AdjuntarComprobanteMantenimientoVehiculoUseCase {
  AdjuntarComprobanteMantenimientoVehiculoUseCase(this._mantenimientoRepository, this._storage);

  final VehiculoMantenimientoRepository _mantenimientoRepository;
  final AttachmentStorage _storage;

  Future<AdjuntarComprobanteMantenimientoVehiculoResultado> ejecutar({
    required String vehiculoMantenimientoId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) async {
    if (await _mantenimientoRepository.obtenerPorId(vehiculoMantenimientoId) == null) {
      return AdjuntarComprobanteMantenimientoVehiculoNoExiste();
    }

    try {
      final guardado = await _storage.guardar(
        ownerId: vehiculoMantenimientoId,
        categoria: 'mantenimiento',
        sourceFilePath: sourceFilePath,
        originalFileName: originalFileName,
      );
      final adjunto = await _mantenimientoRepository.adjuntarArchivo(
        vehiculoMantenimientoId: vehiculoMantenimientoId,
        originalFileName: originalFileName,
        storedFileName: guardado.storedFileName,
        path: guardado.path,
        mimeType: mimeType,
        sizeBytes: guardado.sizeBytes,
      );
      return AdjuntarComprobanteMantenimientoVehiculoExitoso(adjunto);
    } catch (e) {
      return AdjuntarComprobanteMantenimientoVehiculoErrorInesperado(e.toString());
    }
  }
}
