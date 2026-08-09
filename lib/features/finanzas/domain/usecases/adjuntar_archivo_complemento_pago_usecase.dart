import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/complemento_pago_table.dart';

import '../repositories/complemento_pago_repository.dart';
import 'complemento_pago_validator.dart';

sealed class AdjuntarArchivoComplementoPagoResultado {}

class AdjuntarArchivoComplementoPagoExitoso extends AdjuntarArchivoComplementoPagoResultado {
  AdjuntarArchivoComplementoPagoExitoso(this.adjunto);
  final AttachmentData adjunto;
}

class AdjuntarArchivoComplementoPagoNoExiste extends AdjuntarArchivoComplementoPagoResultado {}

/// El tipo de archivo no corresponde a la categoría (ej. un `.xml` en
/// `pdf`).
class AdjuntarArchivoComplementoPagoTipoArchivoInvalido extends AdjuntarArchivoComplementoPagoResultado {}

class AdjuntarArchivoComplementoPagoErrorInesperado extends AdjuntarArchivoComplementoPagoResultado {
  AdjuntarArchivoComplementoPagoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Adjunta el PDF o XML de un Complemento de pago (Etapa 4J.3) — mismo
/// mecanismo que cualquier otro adjunto (`Attachment`).
class AdjuntarArchivoComplementoPagoUseCase {
  AdjuntarArchivoComplementoPagoUseCase(this._repository, this._storage);

  final ComplementoPagoRepository _repository;
  final AttachmentStorage _storage;

  Future<AdjuntarArchivoComplementoPagoResultado> ejecutar({
    required String complementoPagoId,
    required CategoriaAdjuntoComplementoPago categoria,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) async {
    final complemento = await _repository.obtenerPorId(complementoPagoId);
    if (complemento == null) {
      return AdjuntarArchivoComplementoPagoNoExiste();
    }
    if (!tipoArchivoValidoParaCategoriaComplemento(categoria, mimeType)) {
      return AdjuntarArchivoComplementoPagoTipoArchivoInvalido();
    }

    try {
      final guardado = await _storage.guardar(
        ownerId: complementoPagoId,
        categoria: categoria.name,
        sourceFilePath: sourceFilePath,
        originalFileName: originalFileName,
      );
      final adjunto = await _repository.adjuntarArchivo(
        complementoPagoId: complementoPagoId,
        categoria: categoria.name,
        originalFileName: originalFileName,
        storedFileName: guardado.storedFileName,
        path: guardado.path,
        mimeType: mimeType,
        sizeBytes: guardado.sizeBytes,
      );
      return AdjuntarArchivoComplementoPagoExitoso(adjunto);
    } catch (e) {
      return AdjuntarArchivoComplementoPagoErrorInesperado(e.toString());
    }
  }
}
