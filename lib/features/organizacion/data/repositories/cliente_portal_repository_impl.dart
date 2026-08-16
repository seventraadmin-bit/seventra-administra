import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import '../../domain/repositories/cliente_portal_repository.dart';
import '../../domain/usecases/eliminar_cliente_portal_fisicamente_usecase.dart';

class ClientePortalRepositoryImpl implements ClientePortalRepository {
  ClientePortalRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<ClientePortalData> crear(ClientePortalCompanion datos) {
    return _db.into(_db.clientePortal).insertReturning(datos);
  }

  @override
  Future<ClientePortalData?> obtenerPorId(String id) {
    return (_db.select(_db.clientePortal)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<ClientePortalData>> listarPorCliente(String clienteId) {
    return (_db.select(_db.clientePortal)..where((t) => t.clienteId.equals(clienteId))).get();
  }

  @override
  Future<ClientePortalData> actualizar({required String id, required ClientePortalCompanion cambios}) async {
    await (_db.update(_db.clientePortal)..where((t) => t.id.equals(id))).write(
      cambios.copyWith(updatedAt: Value(DateTime.now())),
    );
    return (_db.select(_db.clientePortal)..where((t) => t.id.equals(id))).getSingle();
  }

  @override
  Future<ClientePortalData> cambiarCicloVida({required String id, required CicloVidaRegistro nuevo}) async {
    await (_db.update(_db.clientePortal)..where((t) => t.id.equals(id))).write(
      ClientePortalCompanion(cicloVidaRegistro: Value(nuevo.name), updatedAt: Value(DateTime.now())),
    );
    return (_db.select(_db.clientePortal)..where((t) => t.id.equals(id))).getSingle();
  }

  /// Elegible solo si ninguna `ConfiguracionCobroVigencia` ni ningún
  /// `DocumentoPorEmitir` lo referencia — el histórico debe seguir
  /// siendo resoluble (mismo criterio de bloqueo que
  /// `PuestoRepositoryImpl.eliminarFisicamente`, adaptado a las 2 FK
  /// reales de `ClientePortal`).
  @override
  Future<EliminarClientePortalFisicamenteResultado> eliminarFisicamente({
    required String id,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final portal = await (_db.select(_db.clientePortal)..where((t) => t.id.equals(id))).getSingleOrNull();
      if (portal == null) return EliminarClientePortalFisicamenteNoExiste();

      final vigencias = await (_db.select(_db.configuracionCobroVigencia)
            ..where((t) => t.clientePortalId.equals(id)))
          .get();
      if (vigencias.isNotEmpty) {
        return EliminarClientePortalFisicamenteTieneDependencias(
          'Tiene ${vigencias.length} Configuración(es) de cobro registrada(s).',
        );
      }

      final documentos = await (_db.select(_db.documentoPorEmitir)..where((t) => t.clientePortalId.equals(id))).get();
      if (documentos.isNotEmpty) {
        return EliminarClientePortalFisicamenteTieneDependencias(
          'Tiene ${documentos.length} documento(s) por emitir registrado(s).',
        );
      }

      await _db.into(_db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'clientePortal',
              entidadIdOriginal: id,
              fechaHora: DateTime.now(),
              motivo: motivo,
              snapshotJson: jsonEncode(portal.toJson()),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );
      await (_db.delete(_db.clientePortal)..where((t) => t.id.equals(id))).go();

      return EliminarClientePortalFisicamenteExitoso();
    });
  }
}
