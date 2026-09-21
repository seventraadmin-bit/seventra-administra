import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/cliente_repository.dart';

sealed class RegistrarLogoClienteResultado {}

class RegistrarLogoClienteExitoso extends RegistrarLogoClienteResultado {
  RegistrarLogoClienteExitoso(this.cliente);
  final ClienteData cliente;
}

class RegistrarLogoClienteNoExiste extends RegistrarLogoClienteResultado {}

class RegistrarLogoClienteErrorInesperado extends RegistrarLogoClienteResultado {
  RegistrarLogoClienteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra o reemplaza el logotipo corporativo de un Cliente (Etapa
/// 16, evolución visual) — mismo criterio exacto que
/// `ActualizarFotografiaEmpleadoUseCase`: crea el nuevo `Attachment`
/// (categoría `logo`, dueño vía `ClienteAttachment`), mueve el puntero
/// `logoAttachmentId` y archiva el logo anterior (nunca lo borra).
class RegistrarLogoClienteUseCase {
  RegistrarLogoClienteUseCase(this._repository, this._attachmentRepository, this._storage);

  final ClienteRepository _repository;
  final AttachmentRepository _attachmentRepository;
  final AttachmentStorage _storage;

  Future<RegistrarLogoClienteResultado> ejecutar({
    required String clienteId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) async {
    final cliente = await _repository.obtenerPorId(clienteId);
    if (cliente == null) return RegistrarLogoClienteNoExiste();

    try {
      final guardado = await _storage.guardar(
        ownerId: clienteId,
        categoria: 'logo',
        sourceFilePath: sourceFilePath,
        originalFileName: originalFileName,
      );
      final adjunto = await _repository.adjuntarLogo(
        clienteId: clienteId,
        originalFileName: originalFileName,
        storedFileName: guardado.storedFileName,
        path: guardado.path,
        mimeType: mimeType,
        sizeBytes: guardado.sizeBytes,
      );
      final actualizado = await _repository.actualizarLogo(clienteId: clienteId, attachmentId: adjunto.id);

      final anteriorId = cliente.logoAttachmentId;
      if (anteriorId != null) {
        await _attachmentRepository.archivar(anteriorId);
      }

      return RegistrarLogoClienteExitoso(actualizado);
    } catch (e) {
      return RegistrarLogoClienteErrorInesperado(e.toString());
    }
  }
}
