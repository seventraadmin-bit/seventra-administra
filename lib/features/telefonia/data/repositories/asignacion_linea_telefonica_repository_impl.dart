import 'package:drift/drift.dart';

import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/asignacion_linea_telefonica_repository.dart';
import '../tables/asignacion_linea_telefonica_table.dart';

class AsignacionLineaTelefonicaRepositoryImpl implements AsignacionLineaTelefonicaRepository {
  AsignacionLineaTelefonicaRepositoryImpl(this._db);

  final AppDatabase _db;

  Future<AsignacionLineaTelefonicaData?> _buscarActivaPorLinea(String lineaTelefonicaId) {
    return (_db.select(_db.asignacionLineaTelefonica)
          ..where((t) => t.lineaTelefonicaId.equals(lineaTelefonicaId) & t.fechaTermino.isNull()))
        .getSingleOrNull();
  }

  @override
  Future<AsignacionLineaTelefonicaData?> obtenerPorId(String asignacionLineaTelefonicaId) {
    return (_db.select(_db.asignacionLineaTelefonica)..where((t) => t.id.equals(asignacionLineaTelefonicaId)))
        .getSingleOrNull();
  }

  @override
  Future<AsignacionLineaTelefonicaData?> obtenerActivaPorLinea(String lineaTelefonicaId) =>
      _buscarActivaPorLinea(lineaTelefonicaId);

  @override
  Future<AsignacionLineaTelefonicaData?> obtenerActivaPorEmpleado(String empleadoId) {
    return (_db.select(_db.asignacionLineaTelefonica)
          ..where((t) => t.empleadoId.equals(empleadoId) & t.fechaTermino.isNull()))
        .getSingleOrNull();
  }

  @override
  Future<Map<String, AsignacionLineaTelefonicaData>> obtenerActivasPorTodasLasLineas() async {
    final filas = await (_db.select(_db.asignacionLineaTelefonica)..where((t) => t.fechaTermino.isNull())).get();
    return {for (final fila in filas) fila.lineaTelefonicaId: fila};
  }

  @override
  Future<AsignacionLineaTelefonicaData?> obtenerActivaPorServicio(String servicioId) {
    return (_db.select(_db.asignacionLineaTelefonica)
          ..where((t) => t.servicioId.equals(servicioId) & t.fechaTermino.isNull()))
        .getSingleOrNull();
  }

  @override
  Future<List<AsignacionLineaTelefonicaData>> listarPorLinea(String lineaTelefonicaId) {
    return (_db.select(_db.asignacionLineaTelefonica)
          ..where((t) => t.lineaTelefonicaId.equals(lineaTelefonicaId))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaInicio)]))
        .get();
  }

  @override
  Future<AsignacionLineaTelefonicaData> crear({
    required String lineaTelefonicaId,
    String? empleadoId,
    String? servicioId,
    required DateTime fechaInicio,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _db.into(_db.asignacionLineaTelefonica).insertReturning(
          AsignacionLineaTelefonicaCompanion.insert(
            lineaTelefonicaId: lineaTelefonicaId,
            empleadoId: Value(empleadoId),
            servicioId: Value(servicioId),
            fechaInicio: fechaInicio,
            observaciones: Value(observaciones),
            actorUsuarioId: Value(actorUsuarioId),
          ),
        );
  }

  @override
  Future<AsignacionLineaTelefonicaData> cerrar({
    required String asignacionLineaTelefonicaId,
    required DateTime fechaTermino,
    required String motivoTermino,
    String? observacionesTermino,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.asignacionLineaTelefonica)..where((t) => t.id.equals(asignacionLineaTelefonicaId))).write(
        AsignacionLineaTelefonicaCompanion(
          fechaTermino: Value(fechaTermino),
          motivoTermino: Value(motivoTermino),
          observacionesTermino: Value(observacionesTermino),
          updatedAt: Value(DateTime.now()),
          actorUsuarioId: Value(actorUsuarioId),
        ),
      );
      return (_db.select(_db.asignacionLineaTelefonica)..where((t) => t.id.equals(asignacionLineaTelefonicaId)))
          .getSingle();
    });
  }

  @override
  Future<AsignacionLineaTelefonicaData> cambiarResponsable({
    required String asignacionLineaTelefonicaActualId,
    required DateTime fecha,
    String? motivoTermino,
    String? observacionesTermino,
    String? nuevoEmpleadoId,
    String? nuevoServicioId,
    String? observacionesNueva,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final actual = await (_db.select(_db.asignacionLineaTelefonica)
            ..where((t) => t.id.equals(asignacionLineaTelefonicaActualId)))
          .getSingle();

      await (_db.update(_db.asignacionLineaTelefonica)..where((t) => t.id.equals(asignacionLineaTelefonicaActualId)))
          .write(
        AsignacionLineaTelefonicaCompanion(
          fechaTermino: Value(fecha),
          motivoTermino: Value(motivoTermino ?? MotivoTerminoAsignacionLineaTelefonica.cambioResponsable.name),
          observacionesTermino: Value(observacionesTermino),
          updatedAt: Value(DateTime.now()),
          actorUsuarioId: Value(actorUsuarioId),
        ),
      );

      return _db.into(_db.asignacionLineaTelefonica).insertReturning(
            AsignacionLineaTelefonicaCompanion.insert(
              lineaTelefonicaId: actual.lineaTelefonicaId,
              empleadoId: Value(nuevoEmpleadoId),
              servicioId: Value(nuevoServicioId),
              fechaInicio: fecha,
              observaciones: Value(observacionesNueva),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );
    });
  }

  @override
  Future<void> cerrarPorBajaEmpleado({
    required String empleadoId,
    required DateTime fecha,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final vigentes = await (_db.select(_db.asignacionLineaTelefonica)
            ..where((t) => t.empleadoId.equals(empleadoId) & t.fechaTermino.isNull()))
          .get();
      if (vigentes.isEmpty) return;

      // Una sola sentencia para todas: o se cierran las dos líneas de
      // la persona, o no se cierra ninguna. Ya estamos dentro de la
      // transacción de la baja laboral, así que un fallo aquí revierte
      // también la baja.
      await (_db.update(_db.asignacionLineaTelefonica)
            ..where((t) => t.empleadoId.equals(empleadoId) & t.fechaTermino.isNull()))
          .write(
        AsignacionLineaTelefonicaCompanion(
          fechaTermino: Value(fecha),
          motivoTermino: Value(MotivoTerminoAsignacionLineaTelefonica.bajaEmpleado.name),
          // El actor de la baja laboral: el cierre derivado conserva
          // quién originó la operación, no queda huérfano.
          actorUsuarioId: actorUsuarioId == null ? const Value.absent() : Value(actorUsuarioId),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  @override
  Future<void> cerrarPorBajaLinea({required String lineaTelefonicaId, required DateTime fecha}) {
    return _db.transaction(() async {
      final activa = await _buscarActivaPorLinea(lineaTelefonicaId);
      if (activa == null) return;

      await (_db.update(_db.asignacionLineaTelefonica)..where((t) => t.id.equals(activa.id))).write(
        AsignacionLineaTelefonicaCompanion(
          fechaTermino: Value(fecha),
          motivoTermino: Value(MotivoTerminoAsignacionLineaTelefonica.bajaLinea.name),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }
}
