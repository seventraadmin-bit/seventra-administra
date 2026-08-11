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
    String? actor,
  }) {
    return _db.into(_db.asignacionLineaTelefonica).insertReturning(
          AsignacionLineaTelefonicaCompanion.insert(
            lineaTelefonicaId: lineaTelefonicaId,
            empleadoId: Value(empleadoId),
            servicioId: Value(servicioId),
            fechaInicio: fechaInicio,
            observaciones: Value(observaciones),
          ),
        );
  }

  @override
  Future<AsignacionLineaTelefonicaData> cerrar({
    required String asignacionLineaTelefonicaId,
    required DateTime fechaTermino,
    required String motivoTermino,
    String? observacionesTermino,
    String? actor,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.asignacionLineaTelefonica)..where((t) => t.id.equals(asignacionLineaTelefonicaId))).write(
        AsignacionLineaTelefonicaCompanion(
          fechaTermino: Value(fechaTermino),
          motivoTermino: Value(motivoTermino),
          observacionesTermino: Value(observacionesTermino),
          updatedAt: Value(DateTime.now()),
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
    String? observacionesTermino,
    String? nuevoEmpleadoId,
    String? nuevoServicioId,
    String? observacionesNueva,
    String? actor,
  }) {
    return _db.transaction(() async {
      final actual = await (_db.select(_db.asignacionLineaTelefonica)
            ..where((t) => t.id.equals(asignacionLineaTelefonicaActualId)))
          .getSingle();

      await (_db.update(_db.asignacionLineaTelefonica)..where((t) => t.id.equals(asignacionLineaTelefonicaActualId)))
          .write(
        AsignacionLineaTelefonicaCompanion(
          fechaTermino: Value(fecha),
          motivoTermino: Value(MotivoTerminoAsignacionLineaTelefonica.cambioResponsable.name),
          observacionesTermino: Value(observacionesTermino),
          updatedAt: Value(DateTime.now()),
        ),
      );

      return _db.into(_db.asignacionLineaTelefonica).insertReturning(
            AsignacionLineaTelefonicaCompanion.insert(
              lineaTelefonicaId: actual.lineaTelefonicaId,
              empleadoId: Value(nuevoEmpleadoId),
              servicioId: Value(nuevoServicioId),
              fechaInicio: fecha,
              observaciones: Value(observacionesNueva),
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
