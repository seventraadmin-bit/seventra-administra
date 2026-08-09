import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/attachment_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';

import '../repositories/documento_por_emitir_repository.dart';
import 'adjunto_documento_por_emitir_validator.dart';

sealed class ReemplazarArchivoDocumentoPorEmitirResultado {}

class ReemplazarArchivoDocumentoPorEmitirExitoso extends ReemplazarArchivoDocumentoPorEmitirResultado {
  ReemplazarArchivoDocumentoPorEmitirExitoso(this.adjunto);
  final AttachmentData adjunto;
}

class ReemplazarArchivoDocumentoPorEmitirDocumentoNoExiste extends ReemplazarArchivoDocumentoPorEmitirResultado {}

class ReemplazarArchivoDocumentoPorEmitirArchivoAnteriorNoExiste extends ReemplazarArchivoDocumentoPorEmitirResultado {}

/// El archivo que se intenta reemplazar ya está archivado (ya fue
/// reemplazado antes) — reemplazar siempre parte de la versión activa
/// vigente, nunca de una ya archivada.
class ReemplazarArchivoDocumentoPorEmitirArchivoYaArchivado extends ReemplazarArchivoDocumentoPorEmitirResultado {}

class ReemplazarArchivoDocumentoPorEmitirCategoriaIncompatible extends ReemplazarArchivoDocumentoPorEmitirResultado {}

class ReemplazarArchivoDocumentoPorEmitirTipoArchivoInvalido extends ReemplazarArchivoDocumentoPorEmitirResultado {}

class ReemplazarArchivoDocumentoPorEmitirErrorInesperado extends ReemplazarArchivoDocumentoPorEmitirResultado {
  ReemplazarArchivoDocumentoPorEmitirErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Reemplaza un adjunto activo por uno nuevo (Etapa 4I.2.2, Resolución
/// 3 de Marlon): nunca `UPDATE` del archivo existente, nunca borrado
/// físico — inserta un `Attachment` nuevo, archiva el anterior
/// (`estado = archivado`) y registra el evento `archivoReemplazado`
/// con categoría/archivo anterior/archivo nuevo/motivo, todo en la
/// misma transacción que `DocumentoPorEmitirRepository.
/// reemplazarArchivo` ya garantiza.
class ReemplazarArchivoDocumentoPorEmitirUseCase {
  ReemplazarArchivoDocumentoPorEmitirUseCase(this._repository, this._attachmentRepository, this._storage);

  final DocumentoPorEmitirRepository _repository;
  final AttachmentRepository _attachmentRepository;
  final AttachmentStorage _storage;

  Future<ReemplazarArchivoDocumentoPorEmitirResultado> ejecutar({
    required String documentoPorEmitirId,
    required String attachmentAnteriorId,
    required CategoriaAdjuntoDocumentoPorEmitir categoria,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
    String? motivo,
  }) async {
    final documento = await _repository.obtenerPorId(documentoPorEmitirId);
    if (documento == null) {
      return ReemplazarArchivoDocumentoPorEmitirDocumentoNoExiste();
    }

    final anterior = await _attachmentRepository.obtenerPorId(attachmentAnteriorId);
    if (anterior == null) {
      return ReemplazarArchivoDocumentoPorEmitirArchivoAnteriorNoExiste();
    }
    if (EstadoAdjunto.values.byName(anterior.estado) != EstadoAdjunto.activo) {
      return ReemplazarArchivoDocumentoPorEmitirArchivoYaArchivado();
    }

    final tipoDocumento = TipoDocumentoCobro.values.byName(documento.tipoDocumento);
    if (!categoriaCompatibleConTipoDocumento(categoria, tipoDocumento)) {
      return ReemplazarArchivoDocumentoPorEmitirCategoriaIncompatible();
    }
    if (!tipoArchivoValidoParaCategoria(categoria, mimeType)) {
      return ReemplazarArchivoDocumentoPorEmitirTipoArchivoInvalido();
    }

    try {
      final guardado = await _storage.guardar(
        documentoPorEmitirId: documentoPorEmitirId,
        categoria: categoria.name,
        sourceFilePath: sourceFilePath,
        originalFileName: originalFileName,
      );
      final adjunto = await _repository.reemplazarArchivo(
        documentoPorEmitirId: documentoPorEmitirId,
        attachmentAnteriorId: attachmentAnteriorId,
        categoria: categoria.name,
        originalFileName: originalFileName,
        storedFileName: guardado.storedFileName,
        path: guardado.path,
        mimeType: mimeType,
        sizeBytes: guardado.sizeBytes,
        motivo: motivo,
      );
      return ReemplazarArchivoDocumentoPorEmitirExitoso(adjunto);
    } catch (e) {
      return ReemplazarArchivoDocumentoPorEmitirErrorInesperado(e.toString());
    }
  }
}
