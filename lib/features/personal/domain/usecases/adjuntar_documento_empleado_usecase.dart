import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/empleado_repository.dart';

/// Categorías de documento del expediente del empleado (Etapa 5A) —
/// `otro` cubre cualquier documento futuro sin abrir una categoría
/// nueva ni una solución paralela (mismo criterio que `otroSoporte` en
/// `CategoriaAdjuntoDocumentoPorEmitir`).
enum CategoriaDocumentoEmpleado {
  ine,
  curp,
  rfc,
  actaNacimiento,
  comprobanteDomicilio,
  nss,
  cartilla,
  licencia,
  certificado,
  constancia,
  contrato,
  perfilPsicologico,
  estudioSocioeconomico,
  antidoping,
  otro,
}

sealed class AdjuntarDocumentoEmpleadoResultado {}

class AdjuntarDocumentoEmpleadoExitoso extends AdjuntarDocumentoEmpleadoResultado {
  AdjuntarDocumentoEmpleadoExitoso(this.adjunto);
  final AttachmentData adjunto;
}

class AdjuntarDocumentoEmpleadoNoExiste extends AdjuntarDocumentoEmpleadoResultado {}

class AdjuntarDocumentoEmpleadoErrorInesperado extends AdjuntarDocumentoEmpleadoResultado {
  AdjuntarDocumentoEmpleadoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Adjunta un documento al expediente de un Empleado (Etapa 5A) — mismo
/// mecanismo que cualquier otro adjunto del proyecto (`Attachment`, vía
/// `EmpleadoAttachment` desde esta etapa), sin restricción de tipo de
/// archivo.
class AdjuntarDocumentoEmpleadoUseCase {
  AdjuntarDocumentoEmpleadoUseCase(this._repository, this._storage);

  final EmpleadoRepository _repository;
  final AttachmentStorage _storage;

  Future<AdjuntarDocumentoEmpleadoResultado> ejecutar({
    required String empleadoId,
    required CategoriaDocumentoEmpleado categoria,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) async {
    final empleado = await _repository.obtenerPorId(empleadoId);
    if (empleado == null) return AdjuntarDocumentoEmpleadoNoExiste();

    try {
      final guardado = await _storage.guardar(
        ownerId: empleadoId,
        categoria: categoria.name,
        sourceFilePath: sourceFilePath,
        originalFileName: originalFileName,
      );
      final adjunto = await _repository.adjuntarDocumento(
        empleadoId: empleadoId,
        categoria: categoria.name,
        originalFileName: originalFileName,
        storedFileName: guardado.storedFileName,
        path: guardado.path,
        mimeType: mimeType,
        sizeBytes: guardado.sizeBytes,
      );
      return AdjuntarDocumentoEmpleadoExitoso(adjunto);
    } catch (e) {
      return AdjuntarDocumentoEmpleadoErrorInesperado(e.toString());
    }
  }
}
