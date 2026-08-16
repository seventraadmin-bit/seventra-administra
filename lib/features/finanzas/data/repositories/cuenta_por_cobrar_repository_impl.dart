import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/cuenta_por_cobrar_repository.dart';

class CuentaPorCobrarRepositoryImpl implements CuentaPorCobrarRepository {
  CuentaPorCobrarRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<CuentaPorCobrarData?> obtenerPorId(String id) {
    return (_db.select(_db.cuentaPorCobrar)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<CuentaPorCobrarData?> obtenerPorDocumentoPorEmitirId(String documentoPorEmitirId) {
    return (_db.select(_db.cuentaPorCobrar)..where((t) => t.documentoPorEmitirId.equals(documentoPorEmitirId)))
        .getSingleOrNull();
  }

  @override
  Future<CuentaPorCobrarData> crear({
    required String documentoPorEmitirId,
    required String clienteId,
    required String tipoDocumento,
    required String metodo,
    required bool requiereComplemento,
    String? folioDocumento,
    String? uuid,
    required DateTime fechaEmisionReal,
    required int importeEmitido,
    DateTime? fechaVencimiento,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final cuenta = await _db.into(_db.cuentaPorCobrar).insertReturning(
            CuentaPorCobrarCompanion.insert(
              documentoPorEmitirId: documentoPorEmitirId,
              clienteId: clienteId,
              tipoDocumento: tipoDocumento,
              metodo: metodo,
              requiereComplemento: Value(requiereComplemento),
              folioDocumento: Value(folioDocumento),
              uuid: Value(uuid),
              fechaEmisionReal: fechaEmisionReal,
              importeEmitido: importeEmitido,
              saldoOriginal: importeEmitido,
              saldoPendiente: importeEmitido,
              fechaVencimiento: Value(fechaVencimiento),
            ),
          );

      await _registrarEvento(
        cuentaPorCobrarId: cuenta.id,
        tipoEvento: 'creada',
        estadoAnterior: null,
        estadoNuevo: cuenta.estatus,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'documentoPorEmitirId': documentoPorEmitirId, 'saldoOriginal': importeEmitido},
      );

      return cuenta;
    });
  }

  @override
  Future<List<CuentaPorCobrarData>> listar({
    String? clienteId,
    String? servicioId,
    String? entidadFiscalId,
    String? tipoDocumento,
    String? estatus,
    String? documentoPorEmitirId,
  }) async {
    if (servicioId != null) {
      final query = _db.select(_db.cuentaPorCobrar).join([
        innerJoin(
          _db.documentoPorEmitirServicio,
          _db.documentoPorEmitirServicio.documentoPorEmitirId.equalsExp(_db.cuentaPorCobrar.documentoPorEmitirId),
        ),
      ])
        ..where(_db.documentoPorEmitirServicio.servicioId.equals(servicioId));
      _aplicarFiltrosComunes(
        query,
        clienteId: clienteId,
        tipoDocumento: tipoDocumento,
        estatus: estatus,
        documentoPorEmitirId: documentoPorEmitirId,
      );
      final filas = await query.get();
      return [for (final f in filas) f.readTable(_db.cuentaPorCobrar)];
    }

    if (entidadFiscalId != null) {
      final query = _db.select(_db.cuentaPorCobrar).join([
        innerJoin(
          _db.documentoPorEmitir,
          _db.documentoPorEmitir.id.equalsExp(_db.cuentaPorCobrar.documentoPorEmitirId),
        ),
      ])
        ..where(_db.documentoPorEmitir.entidadFiscalId.equals(entidadFiscalId));
      _aplicarFiltrosComunes(
        query,
        clienteId: clienteId,
        tipoDocumento: tipoDocumento,
        estatus: estatus,
        documentoPorEmitirId: documentoPorEmitirId,
      );
      final filas = await query.get();
      return [for (final f in filas) f.readTable(_db.cuentaPorCobrar)];
    }

    final query = _db.select(_db.cuentaPorCobrar);
    if (clienteId != null) query.where((t) => t.clienteId.equals(clienteId));
    if (tipoDocumento != null) query.where((t) => t.tipoDocumento.equals(tipoDocumento));
    if (estatus != null) query.where((t) => t.estatus.equals(estatus));
    if (documentoPorEmitirId != null) query.where((t) => t.documentoPorEmitirId.equals(documentoPorEmitirId));
    query.orderBy([(t) => OrderingTerm.asc(t.fechaVencimiento)]);
    return query.get();
  }

  void _aplicarFiltrosComunes(
    JoinedSelectStatement query, {
    required String? clienteId,
    required String? tipoDocumento,
    required String? estatus,
    required String? documentoPorEmitirId,
  }) {
    if (clienteId != null) query.where(_db.cuentaPorCobrar.clienteId.equals(clienteId));
    if (tipoDocumento != null) query.where(_db.cuentaPorCobrar.tipoDocumento.equals(tipoDocumento));
    if (estatus != null) query.where(_db.cuentaPorCobrar.estatus.equals(estatus));
    if (documentoPorEmitirId != null) {
      query.where(_db.cuentaPorCobrar.documentoPorEmitirId.equals(documentoPorEmitirId));
    }
  }

  @override
  Future<CuentaPorCobrarData> actualizarFechaVencimiento({
    required String cuentaPorCobrarId,
    required DateTime fechaVencimiento,
    String? motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior =
          await (_db.select(_db.cuentaPorCobrar)..where((t) => t.id.equals(cuentaPorCobrarId))).getSingle();

      await (_db.update(_db.cuentaPorCobrar)..where((t) => t.id.equals(cuentaPorCobrarId))).write(
        CuentaPorCobrarCompanion(
          fechaVencimiento: Value(fechaVencimiento),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEvento(
        cuentaPorCobrarId: cuentaPorCobrarId,
        tipoEvento: 'fechaVencimientoDefinida',
        estadoAnterior: anterior.estatus,
        estadoNuevo: anterior.estatus,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'fechaVencimientoAnterior': anterior.fechaVencimiento?.toIso8601String(),
          'fechaVencimientoNueva': fechaVencimiento.toIso8601String(),
        },
      );

      return (_db.select(_db.cuentaPorCobrar)..where((t) => t.id.equals(cuentaPorCobrarId))).getSingle();
    });
  }

  @override
  Future<List<CuentaPorCobrarEventoData>> listarEventos(String cuentaPorCobrarId) {
    return (_db.select(_db.cuentaPorCobrarEvento)
          ..where((t) => t.cuentaPorCobrarId.equals(cuentaPorCobrarId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaHora)]))
        .get();
  }

  Future<void> _registrarEvento({
    required String cuentaPorCobrarId,
    required String tipoEvento,
    required String? estadoAnterior,
    required String? estadoNuevo,
    String? observacion,
    String? actorUsuarioId,
    Map<String, Object?>? datosRelevantes,
  }) {
    return _db.into(_db.cuentaPorCobrarEvento).insert(
          CuentaPorCobrarEventoCompanion.insert(
            cuentaPorCobrarId: cuentaPorCobrarId,
            fechaHora: DateTime.now(),
            tipoEvento: tipoEvento,
            estadoAnterior: Value(estadoAnterior),
            estadoNuevo: Value(estadoNuevo),
            observacion: Value(observacion),
            actorUsuarioId: Value(actorUsuarioId),
            datosRelevantes: Value(datosRelevantes == null ? null : jsonEncode(datosRelevantes)),
          ),
        );
  }
}
