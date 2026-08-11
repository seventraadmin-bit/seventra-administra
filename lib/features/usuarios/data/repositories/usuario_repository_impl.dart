import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import '../../domain/repositories/usuario_repository.dart';
import '../tables/usuario_table.dart';

class UsuarioRepositoryImpl implements UsuarioRepository {
  UsuarioRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<UsuarioData?> obtenerPorId(String id) {
    return (_db.select(_db.usuario)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<UsuarioData?> obtenerPorNombreUsuario(String nombreUsuario) {
    return (_db.select(_db.usuario)..where((t) => t.nombreUsuario.equals(nombreUsuario))).getSingleOrNull();
  }

  @override
  Future<List<UsuarioData>> listar({String? cicloVidaRegistro}) {
    final query = _db.select(_db.usuario);
    if (cicloVidaRegistro != null) query.where((t) => t.cicloVidaRegistro.equals(cicloVidaRegistro));
    query.orderBy([(t) => OrderingTerm.asc(t.nombre)]);
    return query.get();
  }

  @override
  Future<int> contarUsuarios() async {
    final query = _db.selectOnly(_db.usuario)..addColumns([_db.usuario.id.count()]);
    final row = await query.getSingle();
    return row.read(_db.usuario.id.count()) ?? 0;
  }

  @override
  Future<int> contarMaestrosActivos({String? excluirUsuarioId}) async {
    final query = _db.selectOnly(_db.usuario)..addColumns([_db.usuario.id.count()]);
    query.where(_db.usuario.esMaestro.equals(true) & _db.usuario.cicloVidaRegistro.equals('activo'));
    if (excluirUsuarioId != null) {
      query.where(_db.usuario.id.equals(excluirUsuarioId).not());
    }
    final row = await query.getSingle();
    return row.read(_db.usuario.id.count()) ?? 0;
  }

  @override
  Future<List<UsuarioEventoData>> listarEventos(String usuarioId) {
    return (_db.select(_db.usuarioEvento)
          ..where((t) => t.usuarioId.equals(usuarioId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaHora)]))
        .get();
  }

  @override
  Future<UsuarioData> crear({
    required String nombre,
    required String nombreUsuario,
    required String passwordHash,
    String? puestoId,
    bool esMaestro = false,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final usuario = await _db.into(_db.usuario).insertReturning(
            UsuarioCompanion.insert(
              nombre: nombre,
              nombreUsuario: nombreUsuario,
              passwordHash: passwordHash,
              puestoId: Value(puestoId),
              esMaestro: Value(esMaestro),
            ),
          );

      await _registrarEventoInterno(
        usuarioId: usuario.id,
        tipoEvento: TipoEventoUsuario.creado,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'nombreUsuario': nombreUsuario, 'esMaestro': esMaestro},
      );

      return usuario;
    });
  }

  @override
  Future<UsuarioData> corregir({
    required String usuarioId,
    String? nombre,
    String? nombreUsuario,
    String? puestoId,
    bool? esMaestro,
    String? actorUsuarioId,
    String? motivo,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.usuario)..where((t) => t.id.equals(usuarioId))).getSingle();

      await (_db.update(_db.usuario)..where((t) => t.id.equals(usuarioId))).write(
        UsuarioCompanion(
          nombre: nombre == null ? const Value.absent() : Value(nombre),
          nombreUsuario: nombreUsuario == null ? const Value.absent() : Value(nombreUsuario),
          puestoId: puestoId == null ? const Value.absent() : Value(puestoId),
          esMaestro: esMaestro == null ? const Value.absent() : Value(esMaestro),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEventoInterno(
        usuarioId: usuarioId,
        tipoEvento: TipoEventoUsuario.datosCorregidos,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'nombreAnterior': anterior.nombre,
          'nombreUsuarioAnterior': anterior.nombreUsuario,
          'puestoIdAnterior': anterior.puestoId,
          'esMaestroAnterior': anterior.esMaestro,
        },
      );

      return (_db.select(_db.usuario)..where((t) => t.id.equals(usuarioId))).getSingle();
    });
  }

  @override
  Future<UsuarioData> cambiarContrasena({
    required String usuarioId,
    required String passwordHash,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.usuario)..where((t) => t.id.equals(usuarioId))).write(
        UsuarioCompanion(passwordHash: Value(passwordHash), updatedAt: Value(DateTime.now())),
      );

      await _registrarEventoInterno(
        usuarioId: usuarioId,
        tipoEvento: TipoEventoUsuario.contrasenaCambiada,
        actorUsuarioId: actorUsuarioId,
      );

      return (_db.select(_db.usuario)..where((t) => t.id.equals(usuarioId))).getSingle();
    });
  }

  @override
  Future<UsuarioData> activar({required String usuarioId, String? actorUsuarioId}) {
    return _db.transaction(() async {
      await (_db.update(_db.usuario)..where((t) => t.id.equals(usuarioId))).write(
        UsuarioCompanion(
          cicloVidaRegistro: Value(CicloVidaRegistro.activo.name),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEventoInterno(usuarioId: usuarioId, tipoEvento: TipoEventoUsuario.activado, actorUsuarioId: actorUsuarioId);

      return (_db.select(_db.usuario)..where((t) => t.id.equals(usuarioId))).getSingle();
    });
  }

  @override
  Future<UsuarioData> desactivar({required String usuarioId, String? actorUsuarioId, String? motivo}) {
    return _db.transaction(() async {
      await (_db.update(_db.usuario)..where((t) => t.id.equals(usuarioId))).write(
        UsuarioCompanion(
          cicloVidaRegistro: Value(CicloVidaRegistro.inactivo.name),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEventoInterno(
        usuarioId: usuarioId,
        tipoEvento: TipoEventoUsuario.desactivado,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
      );

      return (_db.select(_db.usuario)..where((t) => t.id.equals(usuarioId))).getSingle();
    });
  }

  @override
  Future<UsuarioData> registrarUltimoAcceso(String usuarioId) {
    return _db.transaction(() async {
      await (_db.update(_db.usuario)..where((t) => t.id.equals(usuarioId))).write(
        UsuarioCompanion(ultimoAccesoAt: Value(DateTime.now())),
      );
      return (_db.select(_db.usuario)..where((t) => t.id.equals(usuarioId))).getSingle();
    });
  }

  Future<void> _registrarEventoInterno({
    required String usuarioId,
    required TipoEventoUsuario tipoEvento,
    String? observacion,
    String? actorUsuarioId,
    Map<String, dynamic>? datosRelevantes,
  }) {
    return _db.into(_db.usuarioEvento).insert(
          UsuarioEventoCompanion.insert(
            usuarioId: usuarioId,
            actorUsuarioId: Value(actorUsuarioId),
            fechaHora: DateTime.now(),
            tipoEvento: tipoEvento.name,
            observacion: Value(observacion),
            datosRelevantes: datosRelevantes == null ? const Value.absent() : Value(jsonEncode(datosRelevantes)),
          ),
        );
  }
}
