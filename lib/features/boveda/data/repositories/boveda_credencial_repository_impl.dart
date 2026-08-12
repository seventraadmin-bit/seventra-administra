import 'package:drift/drift.dart';

import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/boveda_credencial_repository.dart';

class BovedaCredencialRepositoryImpl implements BovedaCredencialRepository {
  BovedaCredencialRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<BovedaCredencialData?> obtenerPorId(String id) {
    return (_db.select(_db.bovedaCredencial)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<BovedaCredencialData>> listar({String? tipo, bool? soloActivos, String? texto}) {
    final query = _db.select(_db.bovedaCredencial);
    if (tipo != null) query.where((t) => t.tipo.equals(tipo));
    if (soloActivos == true) query.where((t) => t.cicloVidaRegistro.equals('activo'));
    if (texto != null && texto.trim().isNotEmpty) {
      final patron = '%${texto.trim()}%';
      query.where((t) => t.nombre.like(patron));
    }
    query.orderBy([(t) => OrderingTerm.asc(t.nombre)]);
    return query.get();
  }

  @override
  Future<BovedaCredencialData> crear({
    required String nombre,
    required String tipo,
    String? usuarioAcceso,
    String? correo,
    String? secretoCifrado,
    DateTime? fechaActualizacionSecreto,
    String? url,
    String? observaciones,
  }) {
    return _db.into(_db.bovedaCredencial).insertReturning(
          BovedaCredencialCompanion.insert(
            nombre: nombre,
            tipo: tipo,
            usuarioAcceso: Value(usuarioAcceso),
            correo: Value(correo),
            secretoCifrado: Value(secretoCifrado),
            fechaActualizacionSecreto: Value(fechaActualizacionSecreto),
            url: Value(url),
            observaciones: Value(observaciones),
          ),
        );
  }

  @override
  Future<BovedaCredencialData> actualizar({
    required String id,
    required String nombre,
    required String tipo,
    String? usuarioAcceso,
    String? correo,
    String? url,
    String? observaciones,
    bool limpiarUsuarioAcceso = false,
    bool limpiarCorreo = false,
    bool limpiarUrl = false,
    bool limpiarObservaciones = false,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.bovedaCredencial)..where((t) => t.id.equals(id))).write(
        BovedaCredencialCompanion(
          nombre: Value(nombre),
          tipo: Value(tipo),
          usuarioAcceso:
              limpiarUsuarioAcceso ? const Value(null) : (usuarioAcceso == null ? const Value.absent() : Value(usuarioAcceso)),
          correo: limpiarCorreo ? const Value(null) : (correo == null ? const Value.absent() : Value(correo)),
          url: limpiarUrl ? const Value(null) : (url == null ? const Value.absent() : Value(url)),
          observaciones: limpiarObservaciones
              ? const Value(null)
              : (observaciones == null ? const Value.absent() : Value(observaciones)),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return (_db.select(_db.bovedaCredencial)..where((t) => t.id.equals(id))).getSingle();
    });
  }

  @override
  Future<BovedaCredencialData> cambiarSecreto({required String id, String? secretoCifrado, required DateTime fecha}) {
    return _db.transaction(() async {
      await (_db.update(_db.bovedaCredencial)..where((t) => t.id.equals(id))).write(
        BovedaCredencialCompanion(
          secretoCifrado: Value(secretoCifrado),
          fechaActualizacionSecreto: Value(fecha),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return (_db.select(_db.bovedaCredencial)..where((t) => t.id.equals(id))).getSingle();
    });
  }

  @override
  Future<BovedaCredencialData> darDeBaja(String id) {
    return _db.transaction(() async {
      await (_db.update(_db.bovedaCredencial)..where((t) => t.id.equals(id))).write(
        BovedaCredencialCompanion(cicloVidaRegistro: const Value('baja'), updatedAt: Value(DateTime.now())),
      );
      return (_db.select(_db.bovedaCredencial)..where((t) => t.id.equals(id))).getSingle();
    });
  }

  @override
  Future<BovedaCredencialData> reactivar(String id) {
    return _db.transaction(() async {
      await (_db.update(_db.bovedaCredencial)..where((t) => t.id.equals(id))).write(
        BovedaCredencialCompanion(cicloVidaRegistro: const Value('activo'), updatedAt: Value(DateTime.now())),
      );
      return (_db.select(_db.bovedaCredencial)..where((t) => t.id.equals(id))).getSingle();
    });
  }

  @override
  Future<void> registrarEvento({
    required String credencialId,
    required String tipoEvento,
    String? actorUsuarioId,
    String? observacion,
  }) {
    return _db.into(_db.bovedaCredencialEvento).insert(
          BovedaCredencialEventoCompanion.insert(
            credencialId: credencialId,
            fechaHora: DateTime.now(),
            tipoEvento: tipoEvento,
            actorUsuarioId: Value(actorUsuarioId),
            observacion: Value(observacion),
          ),
        );
  }

  @override
  Future<List<BovedaCredencialEventoData>> listarEventos(String credencialId) {
    return (_db.select(_db.bovedaCredencialEvento)
          ..where((t) => t.credencialId.equals(credencialId))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaHora)]))
        .get();
  }
}
