import 'package:drift/drift.dart';

import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/conciliacion_baja_repository.dart';
import '../../domain/usecases/conciliar_baja_empleado_usecase.dart';

class ConciliacionBajaRepositoryImpl implements ConciliacionBajaRepository {
  ConciliacionBajaRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<T> enTransaccion<T>(Future<T> Function() operacion) => _db.transaction(operacion);

  @override
  Future<String> crear({
    required String empleadoId,
    required DateTime fechaBaja,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    final fila = await _db.into(_db.conciliacionBaja).insertReturning(
          ConciliacionBajaCompanion.insert(
            empleadoId: empleadoId,
            fechaBaja: fechaBaja,
            observaciones: Value(observaciones),
            actorUsuarioId: Value(actorUsuarioId),
          ),
        );
    return fila.id;
  }

  @override
  Future<void> agregarRenglon({
    required String conciliacionBajaId,
    required ResolucionResguardo resolucion,
    String? descuentoProgramadoId,
  }) async {
    final r = resolucion;
    await _db.into(_db.conciliacionBajaRenglon).insert(
          ConciliacionBajaRenglonCompanion.insert(
            conciliacionBajaId: conciliacionBajaId,
            asignacionId: Value(r.asignacionId),
            asignacionVehiculoId: Value(r.asignacionVehiculoId),
            resolucion: r.resolucion.name,
            condicion: Value(r.condicion?.name),
            destino: Value(r.destino?.name),
            motivoNoEntrega: Value(r.motivoNoEntrega?.name),
            motivoNoEntregaOtro: Value(r.motivoNoEntregaOtro),
            fechaCompromiso: Value(r.fechaCompromiso),
            autorizadorEmpleadoId: Value(r.autorizadorEmpleadoId),
            receptorEmpleadoId: Value(r.receptorEmpleadoId),
            descuentoProgramadoId: Value(descuentoProgramadoId),
            motivoNoCobro: Value(r.motivoNoCobro),
            costoLimpieza: Value(r.costoLimpieza),
            responsableCostoLimpieza: Value(r.responsableCostoLimpieza?.name),
            lugarEntrega: Value(r.lugarEntrega),
            combustible: Value(r.combustible),
            danos: Value(r.danos),
            observaciones: Value(r.observaciones),
          ),
        );
  }

  @override
  Future<List<ConciliacionBajaData>> listar({DateTime? desde, DateTime? hasta}) {
    final query = _db.select(_db.conciliacionBaja);
    if (desde != null) query.where((t) => t.fechaBaja.isBiggerOrEqualValue(desde));
    if (hasta != null) query.where((t) => t.fechaBaja.isSmallerOrEqualValue(hasta));
    query.orderBy([(t) => OrderingTerm.desc(t.fechaBaja)]);
    return query.get();
  }

  @override
  Future<Map<String, List<ConciliacionBajaRenglonData>>> listarRenglonesPorConciliaciones(
    Iterable<String> ids,
  ) async {
    final unicos = ids.toSet();
    if (unicos.isEmpty) return {};
    final filas = await (_db.select(_db.conciliacionBajaRenglon)
          ..where((t) => t.conciliacionBajaId.isIn(unicos))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    final porConciliacion = <String, List<ConciliacionBajaRenglonData>>{};
    for (final fila in filas) {
      porConciliacion.putIfAbsent(fila.conciliacionBajaId, () => []).add(fila);
    }
    return porConciliacion;
  }

  @override
  Future<ConciliacionBajaData?> obtenerPorEmpleado(String empleadoId) {
    return (_db.select(_db.conciliacionBaja)
          ..where((t) => t.empleadoId.equals(empleadoId))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaBaja)])
          ..limit(1))
        .getSingleOrNull();
  }

  @override
  Future<List<ConciliacionBajaRenglonData>> listarRenglones(String conciliacionBajaId) {
    return (_db.select(_db.conciliacionBajaRenglon)
          ..where((t) => t.conciliacionBajaId.equals(conciliacionBajaId))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }
}
