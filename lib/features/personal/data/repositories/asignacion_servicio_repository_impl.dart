import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import '../../domain/repositories/asignacion_servicio_repository.dart';
import '../../domain/usecases/asignacion_sueldo_con_vigencia.dart';
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
  Future<AsignacionServicioData?> obtenerPorId(String asignacionServicioId) {
    return (_db.select(_db.asignacionServicio)..where((t) => t.id.equals(asignacionServicioId))).getSingleOrNull();
  }

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
  Future<List<AsignacionServicioData>> listarTodasActivas() {
    return (_db.select(_db.asignacionServicio)..where((t) => t.fechaTermino.isNull())).get();
  }

  @override
  Future<List<AsignacionServicioData>> listarPorServicio(String servicioId) {
    return (_db.select(_db.asignacionServicio)
          ..where((t) => t.servicioId.equals(servicioId))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaInicio)]))
        .get();
  }

  /// Primera vigencia de sueldo de una asignación recién creada (Etapa
  /// 6B) — siempre abierta (`fechaFinVigencia == null`), fecha de inicio
  /// igual a la de la propia asignación. Ninguna `AsignacionServicio`
  /// existe sin al menos una de estas.
  Future<void> _crearPrimeraVigenciaSueldo({
    required String asignacionServicioId,
    required DateTime fechaInicio,
    required int sueldoMensual,
    required int bonoMensual,
  }) {
    return _db.into(_db.asignacionServicioSueldoVigencia).insert(
          AsignacionServicioSueldoVigenciaCompanion.insert(
            asignacionServicioId: asignacionServicioId,
            sueldoMensual: sueldoMensual,
            bonoMensual: bonoMensual,
            fechaInicioVigencia: fechaInicio,
          ),
        );
  }

  @override
  Future<AsignacionServicioData> asignar({
    required String empleadoId,
    required String servicioId,
    required DateTime fechaInicio,
    required int sueldoMensual,
    required int bonoMensual,
    String? turnoId,
    String? observaciones,
    String? actorUsuarioId,
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
      await _crearPrimeraVigenciaSueldo(
        asignacionServicioId: asignacion.id,
        fechaInicio: fechaInicio,
        sueldoMensual: sueldoMensual,
        bonoMensual: bonoMensual,
      );
      await registrarEventoEmpleado(
        _db,
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.asignacionServicio,
        actorUsuarioId: actorUsuarioId,
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
    required int sueldoMensual,
    required int bonoMensual,
    String? turnoId,
    String? observaciones,
    String? actorUsuarioId,
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
      await _crearPrimeraVigenciaSueldo(
        asignacionServicioId: nueva.id,
        fechaInicio: fecha,
        sueldoMensual: sueldoMensual,
        bonoMensual: bonoMensual,
      );

      await registrarEventoEmpleado(
        _db,
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.cambioServicio,
        actorUsuarioId: actorUsuarioId,
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
    String? actorUsuarioId,
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
        actorUsuarioId: actorUsuarioId,
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

  @override
  Future<List<AsignacionServicioSueldoVigenciaData>> listarVigenciasSueldoActivas(String asignacionServicioId) {
    return (_db.select(_db.asignacionServicioSueldoVigencia)
          ..where(
            (t) =>
                t.asignacionServicioId.equals(asignacionServicioId) &
                t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
          ))
        .get();
  }

  @override
  Future<List<AsignacionServicioSueldoVigenciaData>> listarHistorialSueldo(String asignacionServicioId) {
    return (_db.select(_db.asignacionServicioSueldoVigencia)
          ..where((t) => t.asignacionServicioId.equals(asignacionServicioId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaInicioVigencia)]))
        .get();
  }

  @override
  Future<AsignacionServicioSueldoVigenciaData> registrarVigenciaSueldo({
    required String asignacionServicioId,
    required int sueldoMensual,
    required int bonoMensual,
    required DateTime fechaInicioVigencia,
    String? observaciones,
  }) {
    return _db.transaction(() async {
      final existentes = await listarVigenciasSueldoActivas(asignacionServicioId);
      final inicioNueva = soloFechaSueldo(fechaInicioVigencia);

      // Predecesora: la vigencia `activo` cuyo rango contiene o antecede
      // a la nueva fecha de inicio — a lo más una, por la invariante de
      // no-solapamiento (mismo criterio que `ServicioComercialRepositoryImpl.cambiarVigencia`).
      AsignacionServicioSueldoVigenciaData? predecesora;
      for (final v in existentes) {
        final inicio = soloFechaSueldo(v.fechaInicioVigencia);
        final fin = v.fechaFinVigencia == null ? null : soloFechaSueldo(v.fechaFinVigencia!);
        if (!inicio.isAfter(inicioNueva) && (fin == null || !fin.isBefore(inicioNueva))) {
          if (predecesora == null || inicio.isAfter(soloFechaSueldo(predecesora.fechaInicioVigencia))) {
            predecesora = v;
          }
        }
      }

      if (predecesora != null) {
        await (_db.update(_db.asignacionServicioSueldoVigencia)..where((t) => t.id.equals(predecesora!.id))).write(
          AsignacionServicioSueldoVigenciaCompanion(
            fechaFinVigencia: Value(inicioNueva.subtract(const Duration(days: 1))),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }

      // Sucesora: entre las restantes, la de fecha de inicio más
      // próxima después de la nueva.
      AsignacionServicioSueldoVigenciaData? sucesora;
      for (final v in existentes) {
        if (predecesora != null && v.id == predecesora.id) continue;
        final inicio = soloFechaSueldo(v.fechaInicioVigencia);
        if (inicio.isAfter(inicioNueva)) {
          if (sucesora == null || inicio.isBefore(soloFechaSueldo(sucesora.fechaInicioVigencia))) {
            sucesora = v;
          }
        }
      }

      final fechaFinNueva =
          sucesora != null ? soloFechaSueldo(sucesora.fechaInicioVigencia).subtract(const Duration(days: 1)) : null;

      return _db.into(_db.asignacionServicioSueldoVigencia).insertReturning(
            AsignacionServicioSueldoVigenciaCompanion.insert(
              asignacionServicioId: asignacionServicioId,
              sueldoMensual: sueldoMensual,
              bonoMensual: bonoMensual,
              fechaInicioVigencia: fechaInicioVigencia,
              fechaFinVigencia: Value(fechaFinNueva),
              observaciones: Value(observaciones),
            ),
          );
    });
  }
}
