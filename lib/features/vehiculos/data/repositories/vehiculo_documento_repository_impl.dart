import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/vehiculo_documento_repository.dart';

class VehiculoDocumentoRepositoryImpl implements VehiculoDocumentoRepository {
  VehiculoDocumentoRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<VehiculoDocumentoData?> obtenerPorId(String vehiculoDocumentoId) {
    return (_db.select(_db.vehiculoDocumento)..where((t) => t.id.equals(vehiculoDocumentoId))).getSingleOrNull();
  }

  @override
  Future<List<VehiculoDocumentoData>> listarPorVehiculo(String vehiculoId) {
    return (_db.select(_db.vehiculoDocumento)
          ..where((t) => t.vehiculoId.equals(vehiculoId))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaEmision), (t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  @override
  Future<List<VehiculoDocumentoData>> listarTodos() {
    return (_db.select(_db.vehiculoDocumento)
          ..orderBy([(t) => OrderingTerm.desc(t.fechaEmision), (t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  @override
  Future<VehiculoDocumentoData> crear({
    required String vehiculoId,
    required String tipo,
    String? tipoOtroDescripcion,
    String? numeroFolio,
    DateTime? fechaEmision,
    DateTime? fechaVencimiento,
    String? observaciones,
  }) {
    return _db.into(_db.vehiculoDocumento).insertReturning(
          VehiculoDocumentoCompanion.insert(
            vehiculoId: vehiculoId,
            tipo: tipo,
            tipoOtroDescripcion: Value(tipoOtroDescripcion),
            numeroFolio: Value(numeroFolio),
            fechaEmision: Value(fechaEmision),
            fechaVencimiento: Value(fechaVencimiento),
            observaciones: Value(observaciones),
          ),
        );
  }

  @override
  Future<AttachmentData> adjuntarArchivo({
    required String vehiculoDocumentoId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
  }) {
    return _db.transaction(() async {
      final adjunto = await _db.into(_db.attachment).insertReturning(
            AttachmentCompanion.insert(
              id: const Uuid().v4(),
              originalFileName: originalFileName,
              storedFileName: storedFileName,
              path: path,
              mimeType: mimeType,
              sizeBytes: sizeBytes,
            ),
          );
      await _db.into(_db.vehiculoDocumentoAttachment).insert(
            VehiculoDocumentoAttachmentCompanion.insert(
              attachmentId: adjunto.id,
              vehiculoDocumentoId: vehiculoDocumentoId,
            ),
          );
      return adjunto;
    });
  }
}
