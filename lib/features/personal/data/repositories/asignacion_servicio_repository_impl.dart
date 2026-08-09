import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/asignacion_servicio_repository.dart';
import '../tables/asignacion_servicio_table.dart';
import '../tables/empleado_table.dart';
import 'empleado_evento_writer.dart';

class AsignacionServicioRepositoryImpl implements AsignacionServicioRepository {
  AsignacionServicioRepositoryImpl(this._db);

  final AppDatabase _db;

  Future<AsignacionServicioData?> _buscarActivaPorEmpleado(String empleadoId) {
    return (_db.select(_db.asignacionServicio)
          ..where((t) => t.empleadoId.equals(empleadoId) & t.fechaTermino.isNull()))
        .getSingleOrNull();
  }

  @override
  Future<AsignacionServicioData?> obtenerActivaPorEmpleado(String empleadoId) => _buscarActivaPorEmpleado(empleadoId);

  @override
  Future<List<AsignacionServicioData>> listarPorEmpleado(String empleadoId) {
    return (_db.select(_db.asignacionServicio)
          ..where((t) => t.empleadoId.equals(empleadoId))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaInicio)]))
        .get();
  }

  @override
  Future<List<AsignacionServicioData>> listarActivasPorServicio(String servicioId) {
    return (_db.select(_db.asignacionServicio)
          ..where((t) => t.servicioId.equals(servicioId) & t.fechaTermino.isNull()))
        .get();
  }

  @override
  Future<List<AsignacionServicioData>> listarPorServicio(String servicioId) {
    return (_db.select(_db.asignacionServicio)
          ..where((t) => t.servicioId.equals(servicioId))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaInicio)]))
        .get();
  }

  @override
  Future<AsignacionServicioData> asignar({
    required String empleadoId,
    required String servicioId,
    required DateTime fechaInicio,
    String? turnoId,
    String? observaciones,
    String? actor,
  }) {
    return _db.transaction(() async {
      final asignacion = await _db.into(_db.asignacionServicio).insertReturning(
            AsignacionServicioCompanion.insert(
              empleadoId: empleadoId,
              servicioId: servicioId,
              fechaInicio: fechaInicio,
              turnoId: Value(turnoId),
              observaciones: Value(observaciones),
            ),
          );
      await registrarEventoEmpleado(
        _db,
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.asignacionServicio,
        actor: actor,
        datosRelevantes: {'servicioId': servicioId, if (turnoId != null) 'turnoId': turnoId},
      );
      return asignacion;
    });
  }

  @override
  Future<AsignacionServicioData> cambiarServicio({
    required String empleadoId,
    required String nuevoServicioId,
    required DateTime fecha,
    String? turnoId,
    String? observaciones,
    String? actor,
  }) {
    return _db.transaction(() async {
      final anterior = await _buscarActivaPorEmpleado(empleadoId);
      if (anterior == null) {
        throw StateError('cambiarServicio: el Empleado $empleadoId no tiene una asignación vigente.');
      }

      await (_db.update(_db.asignacionServicio)..where((t) => t.id.equals(anterior.id))).write(
        AsignacionServicioCompanion(
          fechaTermino: Value(fecha),
          motivoTermino: Value(MotivoTerminoAsignacion.cambioServicio.name),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final nueva = await _db.into(_db.asignacionServicio).insertReturning(
            AsignacionServicioCompanion.insert(
              empleadoId: empleadoId,
              servicioId: nuevoServicioId,
              fechaInicio: fecha,
              turnoId: Value(turnoId),
              observaciones: Value(observaciones),
            ),
          );

      await registrarEventoEmpleado(
        _db,
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.cambioServicio,
        actor: actor,
        datosRelevantes: {'servicioAnteriorId': anterior.servicioId, 'servicioNuevoId': nuevoServicioId},
      );
      return nueva;
    });
  }

  @override
  Future<AsignacionServicioData> retirar({
    required String empleadoId,
    required DateTime fechaTermino,
    required String motivo,
    String? observaciones,
    String? actor,
  }) {
    return _db.transaction(() async {
      final activa = await _buscarActivaPorEmpleado(empleadoId);
      if (activa == null) {
        throw StateError('retirar: el Empleado $empleadoId no tiene una asignación vigente.');
      }

      await (_db.update(_db.asignacionServicio)..where((t) => t.id.equals(activa.id))).write(
        AsignacionServicioCompanion(
          fechaTermino: Value(fechaTermino),
          motivoTermino: Value(motivo),
          observacionesTermino: Value(observaciones),
          updatedAt: Value(DateTime.now()),
        ),
      );
      final actualizada = await (_db.select(_db.asignacionServicio)..where((t) => t.id.equals(activa.id))).getSingle();

      await registrarEventoEmpleado(
        _db,
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.retiroServicio,
        actor: actor,
        observacion: observaciones,
        datosRelevantes: {'servicioId': activa.servicioId, 'motivo': motivo},
      );
      return actualizada;
    });
  }

  @override
  Future<void> cerrarPorBajaEmpleado({required String empleadoId, required DateTime fecha}) {
    return _db.transaction(() async {
      final activa = await _buscarActivaPorEmpleado(empleadoId);
      if (activa == null) return;

      await (_db.update(_db.asignacionServicio)..where((t) => t.id.equals(activa.id))).write(
        AsignacionServicioCompanion(
          fechaTermino: Value(fecha),
          motivoTermino: Value(MotivoTerminoAsignacion.bajaEmpleado.name),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await registrarEventoEmpleado(
        _db,
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.retiroServicio,
        observacion: 'Cierre automático por Baja laboral.',
        datosRelevantes: {'servicioId': activa.servicioId, 'motivo': MotivoTerminoAsignacion.bajaEmpleado.name},
      );
    });
  }

  @override
  Future<void> cerrarTodasPorServicioTerminado({required String servicioId, required DateTime fecha}) {
    return _db.transaction(() async {
      final activas = await (_db.select(_db.asignacionServicio)
            ..where((t) => t.servicioId.equals(servicioId) & t.fechaTermino.isNull()))
          .get();

      for (final asignacion in activas) {
        await (_db.update(_db.asignacionServicio)..where((t) => t.id.equals(asignacion.id))).write(
          AsignacionServicioCompanion(
            fechaTermino: Value(fecha),
            motivoTermino: Value(MotivoTerminoAsignacion.servicioTerminado.name),
            updatedAt: Value(DateTime.now()),
          ),
        );
        await registrarEventoEmpleado(
          _db,
          empleadoId: asignacion.empleadoId,
          tipoEvento: TipoEventoEmpleado.retiroServicio,
          observacion: 'Cierre automático por término del Servicio.',
          datosRelevantes: {'servicioId': servicioId, 'motivo': MotivoTerminoAsignacion.servicioTerminado.name},
        );
      }
    });
  }
}
