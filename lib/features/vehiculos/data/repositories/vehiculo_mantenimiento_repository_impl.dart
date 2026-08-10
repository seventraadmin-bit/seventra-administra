import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/vehiculo_mantenimiento_repository.dart';
import '../tables/vehiculo_kilometraje_table.dart';

class VehiculoMantenimientoRepositoryImpl implements VehiculoMantenimientoRepository {
  VehiculoMantenimientoRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<VehiculoMantenimientoData?> obtenerPorId(String vehiculoMantenimientoId) {
    return (_db.select(_db.vehiculoMantenimiento)..where((t) => t.id.equals(vehiculoMantenimientoId)))
        .getSingleOrNull();
  }

  @override
  Future<List<VehiculoMantenimientoData>> listarPorVehiculo(String vehiculoId) {
    return (_db.select(_db.vehiculoMantenimiento)
          ..where((t) => t.vehiculoId.equals(vehiculoId))
          ..orderBy([(t) => OrderingTerm.desc(t.fecha), (t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  @override
  Future<List<VehiculoMantenimientoData>> listarTodos() {
    return _db.select(_db.vehiculoMantenimiento).get();
  }

  @override
  Future<VehiculoMantenimientoData> crear({
    required String vehiculoId,
    required DateTime fecha,
    int? kilometraje,
    required String tipo,
    required String descripcion,
    String? tallerProveedor,
    int? costo,
    DateTime? proximoMantenimientoFecha,
    int? proximoMantenimientoKilometraje,
    String? observaciones,
  }) {
    return _db.transaction(() async {
      final registro = await _db.into(_db.vehiculoMantenimiento).insertReturning(
            VehiculoMantenimientoCompanion.insert(
              vehiculoId: vehiculoId,
              fecha: fecha,
              kilometraje: Value(kilometraje),
              tipo: tipo,
              descripcion: descripcion,
              tallerProveedor: Value(tallerProveedor),
              costo: Value(costo),
              proximoMantenimientoFecha: Value(proximoMantenimientoFecha),
              proximoMantenimientoKilometraje: Value(proximoMantenimientoKilometraje),
              observaciones: Value(observaciones),
            ),
          );

      // Repositorio compone la escritura al ledger de kilometraje
      // (Etapa 8B) directo, sin inyectar `VehiculoKilometrajeRepository`
      // solo para un insert — mismo criterio ya usado por
      // `AsignacionVehiculoRepositoryImpl._registrarKilometraje` (punto
      // 4: "no crear otra fuente paralela de kilometraje").
      if (kilometraje != null) {
        await _db.into(_db.vehiculoKilometraje).insert(
              VehiculoKilometrajeCompanion.insert(
                vehiculoId: vehiculoId,
                fecha: fecha,
                kilometraje: kilometraje,
                origen: OrigenKilometrajeVehiculo.mantenimiento.name,
              ),
            );
      }

      return registro;
    });
  }

  @override
  Future<AttachmentData> adjuntarArchivo({
    required String vehiculoMantenimientoId,
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
      await _db.into(_db.vehiculoMantenimientoAttachment).insert(
            VehiculoMantenimientoAttachmentCompanion.insert(
              attachmentId: adjunto.id,
              vehiculoMantenimientoId: vehiculoMantenimientoId,
            ),
          );
      return adjunto;
    });
  }
}
