import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../tables/cuenta_por_cobrar_table.dart';
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
              documentoPorEmitirId: Value(documentoPorEmitirId),
              clienteId: Value(clienteId),
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
  Future<CuentaPorCobrarData> crearDeServicioEventual({
    required String servicioEventualId,
    String? clienteId,
    required String tipoDocumento,
    required String metodo,
    required bool requiereComplemento,
    required DateTime fechaEmisionReal,
    required int importeEmitido,
    DateTime? fechaVencimiento,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final cuenta = await _db.into(_db.cuentaPorCobrar).insertReturning(
            CuentaPorCobrarCompanion.insert(
              servicioEventualId: Value(servicioEventualId),
              clienteId: Value(clienteId),
              tipoDocumento: tipoDocumento,
              metodo: metodo,
              requiereComplemento: Value(requiereComplemento),
              // Sin folio ni UUID: todavía no existe documento fiscal
              // alguno, y un folio inventado sería peor que un hueco.
              fechaEmisionReal: fechaEmisionReal,
              importeEmitido: importeEmitido,
              saldoOriginal: importeEmitido,
              saldoPendiente: importeEmitido,
              fechaVencimiento: Value(fechaVencimiento),
              observaciones: Value(observaciones),
            ),
          );

      await _registrarEvento(
        cuentaPorCobrarId: cuenta.id,
        tipoEvento: 'creada',
        estadoAnterior: null,
        estadoNuevo: cuenta.estatus,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'servicioEventualId': servicioEventualId, 'saldoOriginal': importeEmitido},
      );

      return cuenta;
    });
  }

  @override
  Future<CuentaPorCobrarData?> obtenerPorServicioEventualId(String servicioEventualId) {
    return (_db.select(_db.cuentaPorCobrar)..where((t) => t.servicioEventualId.equals(servicioEventualId)))
        .getSingleOrNull();
  }

  @override
  Future<Map<String, CuentaPorCobrarData>> porServiciosEventuales(Iterable<String> servicioEventualIds) async {
    final ids = servicioEventualIds.toSet().toList();
    if (ids.isEmpty) return const {};
    final filas =
        await (_db.select(_db.cuentaPorCobrar)..where((t) => t.servicioEventualId.isIn(ids))).get();
    return {for (final f in filas) f.servicioEventualId!: f};
  }

  @override
  Future<CuentaPorCobrarData> sincronizarConDocumentoFiscal({
    required String cuentaPorCobrarId,
    String? folioDocumento,
    String? uuid,
    required DateTime fechaEmisionReal,
    required String metodo,
    required bool requiereComplemento,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior =
          await (_db.select(_db.cuentaPorCobrar)..where((t) => t.id.equals(cuentaPorCobrarId))).getSingle();

      await (_db.update(_db.cuentaPorCobrar)..where((t) => t.id.equals(cuentaPorCobrarId))).write(
        CuentaPorCobrarCompanion(
          folioDocumento: Value(folioDocumento),
          uuid: Value(uuid),
          fechaEmisionReal: Value(fechaEmisionReal),
          metodo: Value(metodo),
          requiereComplemento: Value(requiereComplemento),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final diff = DiffEvento()
        ..anotar('folioDocumento', anterior.folioDocumento, folioDocumento)
        ..anotar('uuid', anterior.uuid, uuid)
        ..anotar('fechaEmisionReal', anterior.fechaEmisionReal, fechaEmisionReal)
        ..anotar('metodo', anterior.metodo, metodo)
        ..anotar('requiereComplemento', anterior.requiereComplemento, requiereComplemento);
      if (diff.hayCambios) {
        await _registrarEvento(
          cuentaPorCobrarId: cuentaPorCobrarId,
          tipoEvento: 'corregida',
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          observacion: 'Sincronización con el documento fiscal del eventual',
          actorUsuarioId: actorUsuarioId,
        );
      }

      return (_db.select(_db.cuentaPorCobrar)..where((t) => t.id.equals(cuentaPorCobrarId))).getSingle();
    });
  }

  @override
  Future<CuentaPorCobrarData> corregirImporte({
    required String cuentaPorCobrarId,
    required int importeEmitido,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior =
          await (_db.select(_db.cuentaPorCobrar)..where((t) => t.id.equals(cuentaPorCobrarId))).getSingle();

      // Los tres campos se fijan a la vez: escribir sólo el importe
      // dejaría `saldo_pendiente > saldo_original` y el CHECK de la
      // tabla rechazaría la escritura. Sin aplicaciones activas (ya
      // validado por el caso de uso) el saldo pendiente ES el total.
      await (_db.update(_db.cuentaPorCobrar)..where((t) => t.id.equals(cuentaPorCobrarId))).write(
        CuentaPorCobrarCompanion(
          importeEmitido: Value(importeEmitido),
          saldoOriginal: Value(importeEmitido),
          saldoPendiente: Value(importeEmitido),
          estatus: Value(EstatusCuentaPorCobrar.pendiente.name),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final diff = DiffEvento()
        ..anotar('importeEmitido', anterior.importeEmitido, importeEmitido)
        ..anotar('saldoOriginal', anterior.saldoOriginal, importeEmitido)
        ..anotar('saldoPendiente', anterior.saldoPendiente, importeEmitido);
      if (diff.hayCambios) {
        await _registrarEvento(
          cuentaPorCobrarId: cuentaPorCobrarId,
          tipoEvento: 'corregida',
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          observacion: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      }

      return (_db.select(_db.cuentaPorCobrar)..where((t) => t.id.equals(cuentaPorCobrarId))).getSingle();
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
    String? servicioEventualId,
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
    if (servicioEventualId != null) query.where((t) => t.servicioEventualId.equals(servicioEventualId));
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
  Future<CuentaPorCobrarData> corregir({
    required String cuentaPorCobrarId,
    DateTime? fechaVencimiento,
    bool limpiarFechaVencimiento = false,
    String? observaciones,
    bool limpiarObservaciones = false,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior =
          await (_db.select(_db.cuentaPorCobrar)..where((t) => t.id.equals(cuentaPorCobrarId))).getSingle();

      final fechaVencimientoFinal =
          limpiarFechaVencimiento ? null : (fechaVencimiento ?? anterior.fechaVencimiento);
      final observacionesFinal = limpiarObservaciones ? null : (observaciones ?? anterior.observaciones);

      await (_db.update(_db.cuentaPorCobrar)..where((t) => t.id.equals(cuentaPorCobrarId))).write(
        CuentaPorCobrarCompanion(
          fechaVencimiento: Value(fechaVencimientoFinal),
          observaciones: Value(observacionesFinal),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final diff = DiffEvento()
        ..anotar('fechaVencimiento', anterior.fechaVencimiento, fechaVencimientoFinal)
        ..anotar('observaciones', anterior.observaciones, observacionesFinal);
      if (diff.hayCambios) {
        await _registrarEvento(
          cuentaPorCobrarId: cuentaPorCobrarId,
          tipoEvento: 'corregida',
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          observacion: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      }

      return (_db.select(_db.cuentaPorCobrar)..where((t) => t.id.equals(cuentaPorCobrarId))).getSingle();
    });
  }

  @override
  Future<CuentaPorCobrarData> reprogramarCobro({
    required String cuentaPorCobrarId,
    required DateTime? fechaCobroReprogramada,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior =
          await (_db.select(_db.cuentaPorCobrar)..where((t) => t.id.equals(cuentaPorCobrarId))).getSingle();

      await (_db.update(_db.cuentaPorCobrar)..where((t) => t.id.equals(cuentaPorCobrarId))).write(
        CuentaPorCobrarCompanion(
          fechaCobroReprogramada: Value(fechaCobroReprogramada),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final diff = DiffEvento()
        ..anotar('fechaCobroReprogramada', anterior.fechaCobroReprogramada, fechaCobroReprogramada);
      if (diff.hayCambios) {
        await _registrarEvento(
          cuentaPorCobrarId: cuentaPorCobrarId,
          tipoEvento: 'fechaCobroReprogramada',
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          observacion: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      }

      return (_db.select(_db.cuentaPorCobrar)..where((t) => t.id.equals(cuentaPorCobrarId))).getSingle();
    });
  }

  @override
  Future<CuentaPorCobrarData> cancelar({
    required String cuentaPorCobrarId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior =
          await (_db.select(_db.cuentaPorCobrar)..where((t) => t.id.equals(cuentaPorCobrarId))).getSingle();

      await (_db.update(_db.cuentaPorCobrar)..where((t) => t.id.equals(cuentaPorCobrarId))).write(
        CuentaPorCobrarCompanion(
          estatus: const Value('cancelada'),
          saldoPendiente: const Value(0),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEvento(
        cuentaPorCobrarId: cuentaPorCobrarId,
        tipoEvento: 'cancelada',
        estadoAnterior: anterior.estatus,
        estadoNuevo: 'cancelada',
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'saldoPendienteAnterior': anterior.saldoPendiente},
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
