import 'package:drift/drift.dart';

import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/linea_telefonica_repository.dart';

class LineaTelefonicaRepositoryImpl implements LineaTelefonicaRepository {
  LineaTelefonicaRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<LineaTelefonicaData?> obtenerPorId(String id) {
    return (_db.select(_db.lineaTelefonica)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<LineaTelefonicaData?> obtenerPorNumero(String numero) {
    return (_db.select(_db.lineaTelefonica)..where((t) => t.numero.equals(numero))).getSingleOrNull();
  }

  @override
  Future<List<LineaTelefonicaData>> listar({bool soloActivos = true}) {
    final query = _db.select(_db.lineaTelefonica);
    if (soloActivos) query.where((t) => t.cicloVidaRegistro.equals('activo'));
    query.orderBy([(t) => OrderingTerm.asc(t.codigo)]);
    return query.get();
  }

  @override
  Future<LineaTelefonicaData> crear({
    required String codigo,
    String? numero,
    required String operador,
    String? operadorOtroNombre,
    required String modalidadSim,
    String? iccid,
    DateTime? fechaActivacion,
    String? observaciones,
  }) {
    return _db.into(_db.lineaTelefonica).insertReturning(
          LineaTelefonicaCompanion.insert(
            codigo: codigo,
            numero: Value(numero),
            operador: operador,
            operadorOtroNombre: Value(operadorOtroNombre),
            modalidadSim: modalidadSim,
            iccid: Value(iccid),
            fechaActivacion: Value(fechaActivacion),
            observaciones: Value(observaciones),
          ),
        );
  }

  @override
  Future<LineaTelefonicaData> corregir({
    required String lineaTelefonicaId,
    String? numero,
    String? operador,
    String? operadorOtroNombre,
    String? modalidadSim,
    String? iccid,
    DateTime? fechaActivacion,
    String? observaciones,
    bool limpiarNumero = false,
    bool limpiarOperadorOtroNombre = false,
    bool limpiarIccid = false,
    bool limpiarFechaActivacion = false,
    bool limpiarObservaciones = false,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.lineaTelefonica)..where((t) => t.id.equals(lineaTelefonicaId))).write(
        LineaTelefonicaCompanion(
          numero: limpiarNumero ? const Value(null) : (numero == null ? const Value.absent() : Value(numero)),
          operador: operador == null ? const Value.absent() : Value(operador),
          operadorOtroNombre: limpiarOperadorOtroNombre
              ? const Value(null)
              : (operadorOtroNombre == null ? const Value.absent() : Value(operadorOtroNombre)),
          modalidadSim: modalidadSim == null ? const Value.absent() : Value(modalidadSim),
          iccid: limpiarIccid ? const Value(null) : (iccid == null ? const Value.absent() : Value(iccid)),
          fechaActivacion: limpiarFechaActivacion
              ? const Value(null)
              : (fechaActivacion == null ? const Value.absent() : Value(fechaActivacion)),
          observaciones: limpiarObservaciones
              ? const Value(null)
              : (observaciones == null ? const Value.absent() : Value(observaciones)),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return (_db.select(_db.lineaTelefonica)..where((t) => t.id.equals(lineaTelefonicaId))).getSingle();
    });
  }

  @override
  Future<LineaTelefonicaData> cambiarEstatus({required String lineaTelefonicaId, required String estatus}) {
    return _db.transaction(() async {
      await (_db.update(_db.lineaTelefonica)..where((t) => t.id.equals(lineaTelefonicaId))).write(
        LineaTelefonicaCompanion(estatus: Value(estatus), updatedAt: Value(DateTime.now())),
      );
      return (_db.select(_db.lineaTelefonica)..where((t) => t.id.equals(lineaTelefonicaId))).getSingle();
    });
  }

  @override
  Future<LineaTelefonicaData> darDeBaja({
    required String lineaTelefonicaId,
    required DateTime fechaBaja,
    required String motivoBaja,
    String? observacionesBaja,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.lineaTelefonica)..where((t) => t.id.equals(lineaTelefonicaId))).write(
        LineaTelefonicaCompanion(
          estatus: const Value('baja'),
          fechaBaja: Value(fechaBaja),
          motivoBaja: Value(motivoBaja),
          observacionesBaja: Value(observacionesBaja),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return (_db.select(_db.lineaTelefonica)..where((t) => t.id.equals(lineaTelefonicaId))).getSingle();
    });
  }
}
