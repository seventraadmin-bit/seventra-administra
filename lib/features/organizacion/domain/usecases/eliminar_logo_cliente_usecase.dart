import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/cliente_repository.dart';

sealed class EliminarLogoClienteResultado {}

class EliminarLogoClienteExitoso extends EliminarLogoClienteResultado {
  EliminarLogoClienteExitoso(this.cliente);
  final ClienteData cliente;
}

class EliminarLogoClienteNoExiste extends EliminarLogoClienteResultado {}

class EliminarLogoClienteSinLogo extends EliminarLogoClienteResultado {}

class EliminarLogoClienteErrorInesperado extends EliminarLogoClienteResultado {
  EliminarLogoClienteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Quita el logotipo vigente de un Cliente (Etapa 16, evolución
/// visual) — a diferencia de la fotografía de Empleado, el logo sí
/// puede quedar explícitamente vacío. El `Attachment` anterior se
/// archiva (nunca se borra), mismo criterio que un reemplazo.
class EliminarLogoClienteUseCase {
  EliminarLogoClienteUseCase(this._repository, this._attachmentRepository);

  final ClienteRepository _repository;
  final AttachmentRepository _attachmentRepository;

  Future<EliminarLogoClienteResultado> ejecutar(String clienteId) async {
    final cliente = await _repository.obtenerPorId(clienteId);
    if (cliente == null) return EliminarLogoClienteNoExiste();

    final anteriorId = cliente.logoAttachmentId;
    if (anteriorId == null) return EliminarLogoClienteSinLogo();

    final actualizado = await _repository.eliminarLogo(clienteId);
    await _attachmentRepository.archivar(anteriorId);

    return EliminarLogoClienteExitoso(actualizado);
  }
}
