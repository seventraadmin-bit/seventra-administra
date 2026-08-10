import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/vehiculo_repository.dart';

class VehiculoRepositoryImpl implements VehiculoRepository {
  VehiculoRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<VehiculoData?> obtenerPorId(String id) {
    return (_db.select(_db.vehiculo)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<VehiculoData?> obtenerPorPlacas(String placas) {
    return (_db.select(_db.vehiculo)..where((t) => t.placas.equals(placas))).getSingleOrNull();
  }

  @override
  Future<VehiculoData?> obtenerPorVin(String vin) {
    return (_db.select(_db.vehiculo)..where((t) => t.vin.equals(vin))).getSingleOrNull();
  }

  @override
  Future<List<VehiculoData>> listar({bool soloActivos = true}) {
    final query = _db.select(_db.vehiculo);
    if (soloActivos) query.where((t) => t.cicloVidaRegistro.equals('activo'));
    query.orderBy([(t) => OrderingTerm.asc(t.marca), (t) => OrderingTerm.asc(t.modelo)]);
    return query.get();
  }

  @override
  Future<VehiculoData> crear({
    required String codigo,
    required String marca,
    required String modelo,
    int? anio,
    String? color,
    String? placas,
    String? vin,
    String? numeroMotor,
    required String tipoVehiculo,
    DateTime? fechaAdquisicion,
    int? costoAdquisicion,
    String? observaciones,
  }) {
    return _db.into(_db.vehiculo).insertReturning(
          VehiculoCompanion.insert(
            codigo: codigo,
            marca: marca,
            modelo: modelo,
            anio: Value(anio),
            color: Value(color),
            placas: Value(placas),
            vin: Value(vin),
            numeroMotor: Value(numeroMotor),
            tipoVehiculo: tipoVehiculo,
            fechaAdquisicion: Value(fechaAdquisicion),
            costoAdquisicion: Value(costoAdquisicion),
            observaciones: Value(observaciones),
          ),
        );
  }

  @override
  Future<VehiculoData> corregir({
    required String vehiculoId,
    String? marca,
    String? modelo,
    int? anio,
    String? color,
    String? placas,
    String? vin,
    String? numeroMotor,
    String? tipoVehiculo,
    DateTime? fechaAdquisicion,
    int? costoAdquisicion,
    String? observaciones,
    bool limpiarAnio = false,
    bool limpiarColor = false,
    bool limpiarPlacas = false,
    bool limpiarVin = false,
    bool limpiarNumeroMotor = false,
    bool limpiarFechaAdquisicion = false,
    bool limpiarCostoAdquisicion = false,
    bool limpiarObservaciones = false,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.vehiculo)..where((t) => t.id.equals(vehiculoId))).write(
        VehiculoCompanion(
          marca: marca == null ? const Value.absent() : Value(marca),
          modelo: modelo == null ? const Value.absent() : Value(modelo),
          anio: limpiarAnio ? const Value(null) : (anio == null ? const Value.absent() : Value(anio)),
          color: limpiarColor ? const Value(null) : (color == null ? const Value.absent() : Value(color)),
          placas: limpiarPlacas ? const Value(null) : (placas == null ? const Value.absent() : Value(placas)),
          vin: limpiarVin ? const Value(null) : (vin == null ? const Value.absent() : Value(vin)),
          numeroMotor: limpiarNumeroMotor
              ? const Value(null)
              : (numeroMotor == null ? const Value.absent() : Value(numeroMotor)),
          tipoVehiculo: tipoVehiculo == null ? const Value.absent() : Value(tipoVehiculo),
          fechaAdquisicion: limpiarFechaAdquisicion
              ? const Value(null)
              : (fechaAdquisicion == null ? const Value.absent() : Value(fechaAdquisicion)),
          costoAdquisicion: limpiarCostoAdquisicion
              ? const Value(null)
              : (costoAdquisicion == null ? const Value.absent() : Value(costoAdquisicion)),
          observaciones: limpiarObservaciones
              ? const Value(null)
              : (observaciones == null ? const Value.absent() : Value(observaciones)),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return (_db.select(_db.vehiculo)..where((t) => t.id.equals(vehiculoId))).getSingle();
    });
  }

  @override
  Future<VehiculoData> cambiarEstatus({required String vehiculoId, required String estatus}) {
    return _db.transaction(() async {
      await (_db.update(_db.vehiculo)..where((t) => t.id.equals(vehiculoId))).write(
        VehiculoCompanion(estatus: Value(estatus), updatedAt: Value(DateTime.now())),
      );
      return (_db.select(_db.vehiculo)..where((t) => t.id.equals(vehiculoId))).getSingle();
    });
  }

  @override
  Future<VehiculoData> darDeBaja({
    required String vehiculoId,
    required DateTime fechaBaja,
    required String motivoBaja,
    String? observacionesBaja,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.vehiculo)..where((t) => t.id.equals(vehiculoId))).write(
        VehiculoCompanion(
          estatus: const Value('baja'),
          fechaBaja: Value(fechaBaja),
          motivoBaja: Value(motivoBaja),
          observacionesBaja: Value(observacionesBaja),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return (_db.select(_db.vehiculo)..where((t) => t.id.equals(vehiculoId))).getSingle();
    });
  }

  @override
  Future<AttachmentData> adjuntarDocumento({
    required String vehiculoId,
    String? categoria,
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
              categoria: Value(categoria),
              originalFileName: originalFileName,
              storedFileName: storedFileName,
              path: path,
              mimeType: mimeType,
              sizeBytes: sizeBytes,
            ),
          );
      await _db.into(_db.vehiculoAttachment).insert(
            VehiculoAttachmentCompanion.insert(attachmentId: adjunto.id, vehiculoId: vehiculoId),
          );
      return adjunto;
    });
  }

  @override
  Future<VehiculoData> actualizarFotografia({required String vehiculoId, required String attachmentId}) {
    return _db.transaction(() async {
      await (_db.update(_db.vehiculo)..where((t) => t.id.equals(vehiculoId))).write(
        VehiculoCompanion(fotografiaAttachmentId: Value(attachmentId), updatedAt: Value(DateTime.now())),
      );
      return (_db.select(_db.vehiculo)..where((t) => t.id.equals(vehiculoId))).getSingle();
    });
  }
}
