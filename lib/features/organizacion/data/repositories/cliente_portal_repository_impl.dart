import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import 'package:riseg_one/core/auditoria/diff_evento.dart';

import '../../domain/repositories/cliente_portal_repository.dart';
import '../tables/comercial_evento_table.dart';
import 'comercial_evento_writer.dart';
import '../../domain/usecases/eliminar_cliente_portal_fisicamente_usecase.dart';

class ClientePortalRepositoryImpl implements ClientePortalRepository {
  ClientePortalRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<ClientePortalData> crear(ClientePortalCompanion datos, {String? actorUsuarioId}) {
    return _db.transaction(() async {
      final creado = await _db.into(_db.clientePortal).insertReturning(datos);

      // La contraseña del portal NUNCA entra a la bitácora: ni en claro
      // ni cifrada. Sólo se registra SI hay una, igual que Bóveda
      // expone metadatos y jamás el secreto.
      await registrarEventoCliente(
        _db,
        clienteId: creado.clienteId,
        tipoEvento: TipoEventoCliente.clientePortalCreado,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'clientePortalId': creado.id,
          'nombre': creado.nombre,
          'tipo': creado.tipo,
          'url': creado.url,
          'usuario': creado.usuario,
          'tieneContrasena': creado.contrasenaCifrada != null,
        },
      );
      return creado;
    });
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
  Future<ClientePortalData> actualizar({
    required String id,
    required ClientePortalCompanion cambios,
    String? motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final antes = await (_db.select(_db.clientePortal)..where((t) => t.id.equals(id))).getSingle();
      await (_db.update(_db.clientePortal)..where((t) => t.id.equals(id))).write(
        cambios.copyWith(updatedAt: Value(DateTime.now())),
      );
      final despues = await (_db.select(_db.clientePortal)..where((t) => t.id.equals(id))).getSingle();

      // `contrasenaCifrada` se compara pero NUNCA se anota con su valor:
      // el diff sólo dice que la contraseña cambió.
      final diff = DiffEvento()
        ..anotar('nombre', antes.nombre, despues.nombre)
        ..anotar('tipo', antes.tipo, despues.tipo)
        ..anotar('url', antes.url, despues.url)
        ..anotar('usuario', antes.usuario, despues.usuario)
        ..anotar('observaciones', antes.observaciones, despues.observaciones);
      final contrasenaCambio = antes.contrasenaCifrada != despues.contrasenaCifrada;
      if (contrasenaCambio) {
        diff.anotar('contrasena', 'sin cambios', 'actualizada');
      }

      if (diff.hayCambios) {
        await registrarEventoCliente(
          _db,
          clienteId: despues.clienteId,
          tipoEvento: TipoEventoCliente.clientePortalCorregido,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          observacion: motivo,
          actorUsuarioId: actorUsuarioId,
          datosRelevantes: {'clientePortalId': id},
        );
      }
      return despues;
    });
  }

  @override
  Future<ClientePortalData> cambiarCicloVida({
    required String id,
    required CicloVidaRegistro nuevo,
    String? motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final antes = await (_db.select(_db.clientePortal)..where((t) => t.id.equals(id))).getSingle();
      await (_db.update(_db.clientePortal)..where((t) => t.id.equals(id))).write(
        ClientePortalCompanion(cicloVidaRegistro: Value(nuevo.name), updatedAt: Value(DateTime.now())),
      );
      final despues = await (_db.select(_db.clientePortal)..where((t) => t.id.equals(id))).getSingle();

      final diff = DiffEvento()
        ..anotar('cicloVidaRegistro', antes.cicloVidaRegistro, despues.cicloVidaRegistro);
      if (diff.hayCambios) {
        await registrarEventoCliente(
          _db,
          clienteId: despues.clienteId,
          tipoEvento: TipoEventoCliente.clientePortalCicloVidaCambiado,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          observacion: motivo,
          actorUsuarioId: actorUsuarioId,
          datosRelevantes: {'clientePortalId': id, 'nombre': despues.nombre},
        );
      }
      return despues;
    });
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
