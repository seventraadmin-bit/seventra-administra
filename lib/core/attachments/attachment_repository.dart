import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Acceso a `Attachment` — infraestructura compartida (Etapa 4A, arco
/// exclusivo extendido en la 4I.2.2), no un módulo de Documentos
/// propio. Sin métodos de eliminación física: el reemplazo archiva la
/// fila anterior (`estado = archivado`), nunca la borra.
class AttachmentRepository {
  AttachmentRepository(this._db);

  final AppDatabase _db;

  Future<AttachmentData> crear(AttachmentCompanion datos) {
    return _db.into(_db.attachment).insertReturning(datos);
  }

  Future<AttachmentData?> obtenerPorId(String id) {
    return (_db.select(_db.attachment)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Solo `estado = activo` — la consulta normal del documento nunca
  /// debe mostrar versiones reemplazadas (Resolución 6 de Marlon).
  Future<List<AttachmentData>> listarActivosPorDocumentoPorEmitir(
    String documentoPorEmitirId, {
    String? categoria,
  }) {
    final query = _db.select(_db.attachment)
      ..where((t) => t.documentoPorEmitirId.equals(documentoPorEmitirId) & t.estado.equals('activo'));
    if (categoria != null) {
      query.where((t) => t.categoria.equals(categoria));
    }
    query.orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.get();
  }

  /// Solo `estado = archivado` — la vía explícita para consultar
  /// versiones anteriores desde el historial (Resolución 6 de Marlon:
  /// nunca se pierde la trazabilidad).
  Future<List<AttachmentData>> listarArchivadosPorDocumentoPorEmitir(String documentoPorEmitirId) {
    return (_db.select(_db.attachment)
          ..where((t) => t.documentoPorEmitirId.equals(documentoPorEmitirId) & t.estado.equals('archivado'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  /// Comprobantes de pago activos de un `Pago` (Etapa 4J.2) — mismo
  /// criterio que los adjuntos de `DocumentoPorEmitir`: solo `estado =
  /// activo`.
  Future<List<AttachmentData>> listarActivosPorPago(String pagoId) {
    return (_db.select(_db.attachment)
          ..where((t) => t.pagoId.equals(pagoId) & t.estado.equals('activo'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  /// Adjuntos (PDF/XML) activos de un `ComplementoPago` (Etapa 4J.3) —
  /// mismo criterio que los adjuntos de `DocumentoPorEmitir`/`Pago`.
  Future<List<AttachmentData>> listarActivosPorComplementoPago(String complementoPagoId) {
    return (_db.select(_db.attachment)
          ..where((t) => t.complementoPagoId.equals(complementoPagoId) & t.estado.equals('activo'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<void> archivar(String id) {
    return (_db.update(_db.attachment)..where((t) => t.id.equals(id))).write(
      const AttachmentCompanion(estado: Value('archivado')),
    );
  }
}
