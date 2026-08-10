import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/vehiculo_repository.dart';

sealed class ActualizarFotografiaVehiculoResultado {}

class ActualizarFotografiaVehiculoExitoso extends ActualizarFotografiaVehiculoResultado {
  ActualizarFotografiaVehiculoExitoso(this.vehiculo);
  final VehiculoData vehiculo;
}

class ActualizarFotografiaVehiculoNoExiste extends ActualizarFotografiaVehiculoResultado {}

class ActualizarFotografiaVehiculoErrorInesperado extends ActualizarFotografiaVehiculoResultado {
  ActualizarFotografiaVehiculoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Reemplaza la fotografía vigente de un Vehículo (Etapa 8A) — mismo
/// criterio exacto que `ActualizarFotografiaEmpleadoUseCase`: crea el
/// nuevo Attachment (categoría `fotografia`, dueño vía
/// `VehiculoAttachment`), mueve el puntero `fotografiaAttachmentId` y
/// archiva la fotografía anterior (nunca la borra).
class ActualizarFotografiaVehiculoUseCase {
  ActualizarFotografiaVehiculoUseCase(this._repository, this._attachmentRepository, this._storage);

  final VehiculoRepository _repository;
  final AttachmentRepository _attachmentRepository;
  final AttachmentStorage _storage;

  Future<ActualizarFotografiaVehiculoResultado> ejecutar({
    required String vehiculoId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) async {
    final vehiculo = await _repository.obtenerPorId(vehiculoId);
    if (vehiculo == null) return ActualizarFotografiaVehiculoNoExiste();

    try {
      final guardado = await _storage.guardar(
        ownerId: vehiculoId,
        categoria: 'fotografia',
        sourceFilePath: sourceFilePath,
        originalFileName: originalFileName,
      );
      final adjunto = await _repository.adjuntarDocumento(
        vehiculoId: vehiculoId,
        categoria: 'fotografia',
        originalFileName: originalFileName,
        storedFileName: guardado.storedFileName,
        path: guardado.path,
        mimeType: mimeType,
        sizeBytes: guardado.sizeBytes,
      );
      final actualizado = await _repository.actualizarFotografia(vehiculoId: vehiculoId, attachmentId: adjunto.id);

      final anteriorId = vehiculo.fotografiaAttachmentId;
      if (anteriorId != null) {
        await _attachmentRepository.archivar(anteriorId);
      }

      return ActualizarFotografiaVehiculoExitoso(actualizado);
    } catch (e) {
      return ActualizarFotografiaVehiculoErrorInesperado(e.toString());
    }
  }
}
