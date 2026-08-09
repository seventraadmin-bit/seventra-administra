import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/attachment_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';

import '../repositories/documento_por_emitir_repository.dart';
import 'adjunto_documento_por_emitir_validator.dart';

sealed class AdjuntarArchivoDocumentoPorEmitirResultado {}

class AdjuntarArchivoDocumentoPorEmitirExitoso extends AdjuntarArchivoDocumentoPorEmitirResultado {
  AdjuntarArchivoDocumentoPorEmitirExitoso(this.adjunto);
  final AttachmentData adjunto;
}

class AdjuntarArchivoDocumentoPorEmitirDocumentoNoExiste extends AdjuntarArchivoDocumentoPorEmitirResultado {}

/// La categoría no aplica al `tipoDocumento` del documento (ej. CFDI
/// PDF/XML en un recibo, recibo PDF en un CFDI) — `otroSoporte` nunca
/// produce este error (Resolución 7 de Marlon).
class AdjuntarArchivoDocumentoPorEmitirCategoriaIncompatible extends AdjuntarArchivoDocumentoPorEmitirResultado {}

/// El tipo de archivo no corresponde a la categoría (ej. un `.xml` en
/// `reciboPdf`) — nunca aplica a `otroSoporte`.
class AdjuntarArchivoDocumentoPorEmitirTipoArchivoInvalido extends AdjuntarArchivoDocumentoPorEmitirResultado {}

class AdjuntarArchivoDocumentoPorEmitirErrorInesperado extends AdjuntarArchivoDocumentoPorEmitirResultado {
  AdjuntarArchivoDocumentoPorEmitirErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Adjunta un archivo nuevo a un `DocumentoPorEmitir` (Etapa 4I.2.2) —
/// primero lo guarda físicamente bajo `AppPaths.attachmentsDir`
/// (`AttachmentStorage`, que nunca usa `originalFileName` como nombre
/// físico), luego inserta el registro y el evento `archivoAdjuntado`
/// en una sola transacción (`DocumentoPorEmitirRepository.
/// adjuntarArchivo`). Varios archivos por categoría son válidos — esto
/// nunca reemplaza uno existente (para eso está
/// `ReemplazarArchivoDocumentoPorEmitirUseCase`).
class AdjuntarArchivoDocumentoPorEmitirUseCase {
  AdjuntarArchivoDocumentoPorEmitirUseCase(this._repository, this._storage);

  final DocumentoPorEmitirRepository _repository;
  final AttachmentStorage _storage;

  Future<AdjuntarArchivoDocumentoPorEmitirResultado> ejecutar({
    required String documentoPorEmitirId,
    required CategoriaAdjuntoDocumentoPorEmitir categoria,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) async {
    final documento = await _repository.obtenerPorId(documentoPorEmitirId);
    if (documento == null) {
      return AdjuntarArchivoDocumentoPorEmitirDocumentoNoExiste();
    }

    final tipoDocumento = TipoDocumentoCobro.values.byName(documento.tipoDocumento);
    if (!categoriaCompatibleConTipoDocumento(categoria, tipoDocumento)) {
      return AdjuntarArchivoDocumentoPorEmitirCategoriaIncompatible();
    }
    if (!tipoArchivoValidoParaCategoria(categoria, mimeType)) {
      return AdjuntarArchivoDocumentoPorEmitirTipoArchivoInvalido();
    }

    try {
      final guardado = await _storage.guardar(
        ownerId: documentoPorEmitirId,
        categoria: categoria.name,
        sourceFilePath: sourceFilePath,
        originalFileName: originalFileName,
      );
      final adjunto = await _repository.adjuntarArchivo(
        documentoPorEmitirId: documentoPorEmitirId,
        categoria: categoria.name,
        originalFileName: originalFileName,
        storedFileName: guardado.storedFileName,
        path: guardado.path,
        mimeType: mimeType,
        sizeBytes: guardado.sizeBytes,
      );
      return AdjuntarArchivoDocumentoPorEmitirExitoso(adjunto);
    } catch (e) {
      return AdjuntarArchivoDocumentoPorEmitirErrorInesperado(e.toString());
    }
  }
}
