import 'package:drift/drift.dart';

import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/asignacion_vehiculo_repository.dart';
import '../tables/asignacion_vehiculo_table.dart';
import '../tables/vehiculo_kilometraje_table.dart';

class AsignacionVehiculoRepositoryImpl implements AsignacionVehiculoRepository {
  AsignacionVehiculoRepositoryImpl(this._db);

  final AppDatabase _db;

  Future<AsignacionVehiculoData?> _buscarActivaPorVehiculo(String vehiculoId) {
    return (_db.select(_db.asignacionVehiculo)
          ..where((t) => t.vehiculoId.equals(vehiculoId) & t.fechaTermino.isNull()))
        .getSingleOrNull();
  }

  Future<void> _actualizarEstatusVehiculoSiNoTerminal(String vehiculoId, String estatusDeseado) async {
    final vehiculo = await (_db.select(_db.vehiculo)..where((t) => t.id.equals(vehiculoId))).getSingle();
    if (vehiculo.estatus != 'asignado') return;
    await (_db.update(_db.vehiculo)..where((t) => t.id.equals(vehiculoId))).write(
      VehiculoCompanion(estatus: Value(estatusDeseado), updatedAt: Value(DateTime.now())),
    );
  }

  @override
  Future<AsignacionVehiculoData?> obtenerPorId(String asignacionVehiculoId) {
    return (_db.select(_db.asignacionVehiculo)..where((t) => t.id.equals(asignacionVehiculoId))).getSingleOrNull();
  }

  @override
  Future<AsignacionVehiculoData?> obtenerActivaPorVehiculo(String vehiculoId) => _buscarActivaPorVehiculo(vehiculoId);

  @override
  Future<AsignacionVehiculoData?> obtenerActivaPorEmpleado(String empleadoId) {
    return (_db.select(_db.asignacionVehiculo)
          ..where((t) => t.empleadoId.equals(empleadoId) & t.fechaTermino.isNull()))
        .getSingleOrNull();
  }

  @override
  Future<AsignacionVehiculoData?> obtenerActivaPorServicio(String servicioId) {
    return (_db.select(_db.asignacionVehiculo)
          ..where((t) => t.servicioId.equals(servicioId) & t.fechaTermino.isNull()))
        .getSingleOrNull();
  }

  @override
  Future<List<AsignacionVehiculoData>> listarPorVehiculo(String vehiculoId) {
    return (_db.select(_db.asignacionVehiculo)
          ..where((t) => t.vehiculoId.equals(vehiculoId))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaInicio)]))
        .get();
  }

  Future<void> _registrarKilometraje({
    required String vehiculoId,
    required DateTime fecha,
    required int kilometraje,
    required String origen,
    String? actorUsuarioId,
  }) {
    return _db.into(_db.vehiculoKilometraje).insert(
          VehiculoKilometrajeCompanion.insert(
            vehiculoId: vehiculoId,
            fecha: fecha,
            kilometraje: kilometraje,
            origen: origen,
            actorUsuarioId: Value(actorUsuarioId),
          ),
        );
  }

  @override
  Future<AsignacionVehiculoData> crear({
    required String vehiculoId,
    String? empleadoId,
    String? servicioId,
    required DateTime fechaInicio,
    String? observaciones,
    int? kilometrajeEntrega,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final asignacion = await _db.into(_db.asignacionVehiculo).insertReturning(
            AsignacionVehiculoCompanion.insert(
              vehiculoId: vehiculoId,
              empleadoId: Value(empleadoId),
              servicioId: Value(servicioId),
              fechaInicio: fechaInicio,
              observaciones: Value(observaciones),
            ),
          );
      await (_db.update(_db.vehiculo)..where((t) => t.id.equals(vehiculoId))).write(
        VehiculoCompanion(estatus: const Value('asignado'), updatedAt: Value(DateTime.now())),
      );
      if (kilometrajeEntrega != null) {
        await _registrarKilometraje(
          vehiculoId: vehiculoId,
          fecha: fechaInicio,
          kilometraje: kilometrajeEntrega,
          origen: OrigenKilometrajeVehiculo.entrega.name,
          actorUsuarioId: actorUsuarioId,
        );
      }
      return asignacion;
    });
  }

  @override
  Future<AsignacionVehiculoData> cerrar({
    required String asignacionVehiculoId,
    required DateTime fechaTermino,
    required String motivoTermino,
    String? observacionesTermino,
    int? kilometrajeDevolucion,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final actual = await (_db.select(_db.asignacionVehiculo)..where((t) => t.id.equals(asignacionVehiculoId)))
          .getSingle();

      await (_db.update(_db.asignacionVehiculo)..where((t) => t.id.equals(asignacionVehiculoId))).write(
        AsignacionVehiculoCompanion(
          fechaTermino: Value(fechaTermino),
          motivoTermino: Value(motivoTermino),
          observacionesTermino: Value(observacionesTermino),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _actualizarEstatusVehiculoSiNoTerminal(actual.vehiculoId, 'disponible');
      if (kilometrajeDevolucion != null) {
        await _registrarKilometraje(
          vehiculoId: actual.vehiculoId,
          fecha: fechaTermino,
          kilometraje: kilometrajeDevolucion,
          origen: OrigenKilometrajeVehiculo.devolucion.name,
          actorUsuarioId: actorUsuarioId,
        );
      }

      return (_db.select(_db.asignacionVehiculo)..where((t) => t.id.equals(asignacionVehiculoId))).getSingle();
    });
  }

  @override
  Future<AsignacionVehiculoData> cambiarResponsable({
    required String asignacionVehiculoActualId,
    required DateTime fecha,
    String? observacionesTermino,
    String? nuevoEmpleadoId,
    String? nuevoServicioId,
    String? observacionesNueva,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final actual = await (_db.select(_db.asignacionVehiculo)..where((t) => t.id.equals(asignacionVehiculoActualId)))
          .getSingle();

      await (_db.update(_db.asignacionVehiculo)..where((t) => t.id.equals(asignacionVehiculoActualId))).write(
        AsignacionVehiculoCompanion(
          fechaTermino: Value(fecha),
          motivoTermino: Value(MotivoTerminoAsignacionVehiculo.cambioResponsable.name),
          observacionesTermino: Value(observacionesTermino),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final nueva = await _db.into(_db.asignacionVehiculo).insertReturning(
            AsignacionVehiculoCompanion.insert(
              vehiculoId: actual.vehiculoId,
              empleadoId: Value(nuevoEmpleadoId),
              servicioId: Value(nuevoServicioId),
              fechaInicio: fecha,
              observaciones: Value(observacionesNueva),
            ),
          );
      // El estatus ya era `asignado` (la asignación anterior estaba
      // vigente) — se reafirma explícito en vez de asumirlo, sin costo
      // adicional real.
      await (_db.update(_db.vehiculo)..where((t) => t.id.equals(actual.vehiculoId))).write(
        VehiculoCompanion(estatus: const Value('asignado'), updatedAt: Value(DateTime.now())),
      );

      return nueva;
    });
  }

  @override
  Future<void> cerrarPorBajaVehiculo({required String vehiculoId, required DateTime fecha}) {
    return _db.transaction(() async {
      final activa = await _buscarActivaPorVehiculo(vehiculoId);
      if (activa == null) return;

      await (_db.update(_db.asignacionVehiculo)..where((t) => t.id.equals(activa.id))).write(
        AsignacionVehiculoCompanion(
          fechaTermino: Value(fecha),
          motivoTermino: Value(MotivoTerminoAsignacionVehiculo.bajaVehiculo.name),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }
}
