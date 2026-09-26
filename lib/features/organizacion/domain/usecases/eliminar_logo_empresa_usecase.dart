import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/empresa_repository.dart';

sealed class EliminarLogoEmpresaResultado {}

class EliminarLogoEmpresaExitoso extends EliminarLogoEmpresaResultado {
  EliminarLogoEmpresaExitoso(this.empresa);
  final EmpresaData empresa;
}

class EliminarLogoEmpresaNoExiste extends EliminarLogoEmpresaResultado {}

class EliminarLogoEmpresaSinLogo extends EliminarLogoEmpresaResultado {}

class EliminarLogoEmpresaErrorInesperado extends EliminarLogoEmpresaResultado {
  EliminarLogoEmpresaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Quita el logotipo vigente de una Empresa (Etapa 5B.2).
///
/// Mismo criterio que el logotipo de Cliente: la Empresa **puede** quedarse
/// sin logotipo, y el `Attachment` anterior se archiva, nunca se borra.
///
/// Que el archivado sobreviva importa más aquí que en Cliente: es lo que le
/// dice a la adopción del logotipo heredado que ya hizo su trabajo, de modo
/// que quitar el logo a propósito no lo resucita en el siguiente arranque.
class EliminarLogoEmpresaUseCase {
  EliminarLogoEmpresaUseCase(this._repository, this._attachmentRepository);

  final EmpresaRepository _repository;
  final AttachmentRepository _attachmentRepository;

  Future<EliminarLogoEmpresaResultado> ejecutar(String empresaId) async {
    final empresa = await _repository.obtenerPorId(empresaId);
    if (empresa == null) return EliminarLogoEmpresaNoExiste();

    final anteriorId = empresa.logoAttachmentId;
    if (anteriorId == null) return EliminarLogoEmpresaSinLogo();

    try {
      final actualizada = await _repository.eliminarLogo(empresaId);
      await _attachmentRepository.archivar(anteriorId);
      return EliminarLogoEmpresaExitoso(actualizada);
    } catch (e) {
      return EliminarLogoEmpresaErrorInesperado(e.toString());
    }
  }
}
