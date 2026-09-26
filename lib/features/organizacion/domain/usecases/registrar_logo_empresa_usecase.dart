import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/empresa_repository.dart';
import 'logo_empresa_validacion.dart';

sealed class RegistrarLogoEmpresaResultado {}

class RegistrarLogoEmpresaExitoso extends RegistrarLogoEmpresaResultado {
  RegistrarLogoEmpresaExitoso(this.empresa);
  final EmpresaData empresa;
}

class RegistrarLogoEmpresaNoExiste extends RegistrarLogoEmpresaResultado {}

/// El archivo no pasó la revisión. Lleva el veredicto para que la pantalla
/// pueda decir **por qué** en vez de un "no se pudo" genérico.
class RegistrarLogoEmpresaArchivoInvalido extends RegistrarLogoEmpresaResultado {
  RegistrarLogoEmpresaArchivoInvalido(this.motivo);
  final RevisionLogo motivo;
}

class RegistrarLogoEmpresaErrorInesperado extends RegistrarLogoEmpresaResultado {
  RegistrarLogoEmpresaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra o reemplaza el logotipo de una Empresa (Etapa 5B.2).
///
/// Mismo recorrido que `RegistrarLogoClienteUseCase`: copia el archivo al
/// almacén de adjuntos, crea el `Attachment` con su fila puente, mueve el
/// puntero `logoAttachmentId` y **archiva** el logotipo anterior — nunca lo
/// borra, así que un reemplazo siempre se puede auditar.
///
/// Lo que añade respecto a Cliente es la revisión previa del archivo. El
/// logotipo de la Empresa acaba impreso en documentos que salen a terceros,
/// así que conviene descubrir aquí que alguien eligió un PDF renombrado y no
/// al generar un recibo.
class RegistrarLogoEmpresaUseCase {
  RegistrarLogoEmpresaUseCase(this._repository, this._attachmentRepository, this._storage);

  final EmpresaRepository _repository;
  final AttachmentRepository _attachmentRepository;
  final AttachmentStorage _storage;

  Future<RegistrarLogoEmpresaResultado> ejecutar({
    required String empresaId,
    required String sourceFilePath,
    required String originalFileName,
  }) async {
    final empresa = await _repository.obtenerPorId(empresaId);
    if (empresa == null) return RegistrarLogoEmpresaNoExiste();

    // Se revisa ANTES de copiar: si no pasa, el almacén ni se entera y no
    // queda un archivo huérfano que limpiar.
    final revision = await revisarLogo(sourceFilePath);
    if (revision is! LogoAceptado) return RegistrarLogoEmpresaArchivoInvalido(revision);

    try {
      final guardado = await _storage.guardar(
        ownerId: empresaId,
        categoria: categoriaLogo,
        sourceFilePath: sourceFilePath,
        originalFileName: originalFileName,
      );
      final adjunto = await _repository.adjuntarLogo(
        empresaId: empresaId,
        originalFileName: originalFileName,
        storedFileName: guardado.storedFileName,
        path: guardado.path,
        // El tipo sale de la firma del archivo, no de su extensión.
        mimeType: revision.mimeType,
        sizeBytes: guardado.sizeBytes,
      );
      final actualizada = await _repository.actualizarLogo(empresaId: empresaId, attachmentId: adjunto.id);

      final anteriorId = empresa.logoAttachmentId;
      if (anteriorId != null) await _attachmentRepository.archivar(anteriorId);

      return RegistrarLogoEmpresaExitoso(actualizada);
    } catch (e) {
      return RegistrarLogoEmpresaErrorInesperado(e.toString());
    }
  }
}
