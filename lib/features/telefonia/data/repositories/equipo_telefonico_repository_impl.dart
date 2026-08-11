import 'package:drift/drift.dart';

import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/equipo_telefonico_repository.dart';

class EquipoTelefonicoRepositoryImpl implements EquipoTelefonicoRepository {
  EquipoTelefonicoRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<EquipoTelefonicoCredencialData?> obtenerCredencial(String unidadId) {
    return (_db.select(_db.equipoTelefonicoCredencial)..where((t) => t.unidadId.equals(unidadId))).getSingleOrNull();
  }

  @override
  Future<EquipoTelefonicoCredencialData> guardarCorreo({
    required String unidadId,
    String? correo,
    String? observaciones,
  }) async {
    final existente = await obtenerCredencial(unidadId);
    if (existente == null) {
      return _db.into(_db.equipoTelefonicoCredencial).insertReturning(
            EquipoTelefonicoCredencialCompanion.insert(
              unidadId: unidadId,
              correo: Value(correo),
              observaciones: Value(observaciones),
            ),
          );
    }

    await (_db.update(_db.equipoTelefonicoCredencial)..where((t) => t.unidadId.equals(unidadId))).write(
      EquipoTelefonicoCredencialCompanion(correo: Value(correo), observaciones: Value(observaciones)),
    );
    return (_db.select(_db.equipoTelefonicoCredencial)..where((t) => t.unidadId.equals(unidadId))).getSingle();
  }

  @override
  Future<EquipoTelefonicoCredencialData> guardarContrasena({
    required String unidadId,
    required String contrasenaCifrada,
    required DateTime fecha,
  }) async {
    final existente = await obtenerCredencial(unidadId);
    if (existente == null) {
      return _db.into(_db.equipoTelefonicoCredencial).insertReturning(
            EquipoTelefonicoCredencialCompanion.insert(
              unidadId: unidadId,
              contrasenaCifrada: Value(contrasenaCifrada),
              fechaActualizacionContrasena: Value(fecha),
            ),
          );
    }

    await (_db.update(_db.equipoTelefonicoCredencial)..where((t) => t.unidadId.equals(unidadId))).write(
      EquipoTelefonicoCredencialCompanion(
        contrasenaCifrada: Value(contrasenaCifrada),
        fechaActualizacionContrasena: Value(fecha),
      ),
    );
    return (_db.select(_db.equipoTelefonicoCredencial)..where((t) => t.unidadId.equals(unidadId))).getSingle();
  }

  @override
  Future<void> registrarEvento({
    required String unidadId,
    required String tipoEvento,
    String? actorUsuarioId,
    String? observacion,
  }) {
    return _db.into(_db.equipoTelefonicoEvento).insert(
          EquipoTelefonicoEventoCompanion.insert(
            unidadId: unidadId,
            fechaHora: DateTime.now(),
            tipoEvento: tipoEvento,
            actorUsuarioId: Value(actorUsuarioId),
            observacion: Value(observacion),
          ),
        );
  }

  @override
  Future<List<EquipoTelefonicoEventoData>> listarEventos(String unidadId) {
    return (_db.select(_db.equipoTelefonicoEvento)
          ..where((t) => t.unidadId.equals(unidadId))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaHora)]))
        .get();
  }
}
