import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/empleado_repository.dart';

sealed class ActualizarFotografiaEmpleadoResultado {}

class ActualizarFotografiaEmpleadoExitoso extends ActualizarFotografiaEmpleadoResultado {
  ActualizarFotografiaEmpleadoExitoso(this.empleado);
  final EmpleadoData empleado;
}

class ActualizarFotografiaEmpleadoNoExiste extends ActualizarFotografiaEmpleadoResultado {}

class ActualizarFotografiaEmpleadoErrorInesperado extends ActualizarFotografiaEmpleadoResultado {
  ActualizarFotografiaEmpleadoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Reemplaza la fotografía vigente de un Empleado (Etapa 5A) — crea el
/// nuevo Attachment (categoría `fotografia`, dueño vía
/// `EmpleadoAttachment`), mueve el puntero `fotografiaAttachmentId` y
/// archiva la fotografía anterior (nunca la borra), mismo criterio que
/// `AdjuntarComprobantePagoUseCase`/`DocumentoPorEmitirRepositoryImpl.reemplazarArchivo`.
class ActualizarFotografiaEmpleadoUseCase {
  ActualizarFotografiaEmpleadoUseCase(this._repository, this._attachmentRepository, this._storage);

  final EmpleadoRepository _repository;
  final AttachmentRepository _attachmentRepository;
  final AttachmentStorage _storage;

  Future<ActualizarFotografiaEmpleadoResultado> ejecutar({
    required String empleadoId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) async {
    final empleado = await _repository.obtenerPorId(empleadoId);
    if (empleado == null) return ActualizarFotografiaEmpleadoNoExiste();

    try {
      final guardado = await _storage.guardar(
        ownerId: empleadoId,
        categoria: 'fotografia',
        sourceFilePath: sourceFilePath,
        originalFileName: originalFileName,
      );
      final adjunto = await _repository.adjuntarDocumento(
        empleadoId: empleadoId,
        categoria: 'fotografia',
        originalFileName: originalFileName,
        storedFileName: guardado.storedFileName,
        path: guardado.path,
        mimeType: mimeType,
        sizeBytes: guardado.sizeBytes,
      );
      final actualizado = await _repository.actualizarFotografia(empleadoId: empleadoId, attachmentId: adjunto.id);

      final anteriorId = empleado.fotografiaAttachmentId;
      if (anteriorId != null) {
        await _attachmentRepository.archivar(anteriorId);
      }

      return ActualizarFotografiaEmpleadoExitoso(actualizado);
    } catch (e) {
      return ActualizarFotografiaEmpleadoErrorInesperado(e.toString());
    }
  }
}
