import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/complemento_pago_table.dart';
import 'package:uuid/uuid.dart';

import '../../domain/repositories/complemento_pago_repository.dart';

class ComplementoPagoRepositoryImpl implements ComplementoPagoRepository {
  ComplementoPagoRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<ComplementoPagoData?> obtenerPorId(String id) {
    return (_db.select(_db.complementoPago)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<ComplementoPagoData?> obtenerPorPagoId(String pagoId) {
    return (_db.select(_db.complementoPago)..where((t) => t.pagoId.equals(pagoId))).getSingleOrNull();
  }

  @override
  Future<ComplementoPagoData?> obtenerPorUuid(String uuid) {
    return (_db.select(_db.complementoPago)..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
  }

  @override
  Future<List<ComplementoPagoData>> listar({
    String? clienteId,
    String? estatus,
    DateTime? rangoInicio,
    DateTime? rangoFin,
  }) {
    if (clienteId != null) {
      final query = _db.select(_db.complementoPago).join([
        innerJoin(_db.pago, _db.pago.id.equalsExp(_db.complementoPago.pagoId)),
      ])
        ..where(_db.pago.clienteId.equals(clienteId));
      if (estatus != null) query.where(_db.complementoPago.estatus.equals(estatus));
      if (rangoInicio != null) query.where(_db.complementoPago.fechaTimbrado.isBiggerOrEqualValue(rangoInicio));
      if (rangoFin != null) query.where(_db.complementoPago.fechaTimbrado.isSmallerOrEqualValue(rangoFin));
      return query.map((row) => row.readTable(_db.complementoPago)).get();
    }

    final query = _db.select(_db.complementoPago);
    if (estatus != null) query.where((t) => t.estatus.equals(estatus));
    if (rangoInicio != null) query.where((t) => t.fechaTimbrado.isBiggerOrEqualValue(rangoInicio));
    if (rangoFin != null) query.where((t) => t.fechaTimbrado.isSmallerOrEqualValue(rangoFin));
    query.orderBy([(t) => OrderingTerm.desc(t.fechaTimbrado)]);
    return query.get();
  }

  @override
  Future<List<ComplementoPagoEventoData>> listarEventos(String complementoPagoId) {
    return (_db.select(_db.complementoPagoEvento)
          ..where((t) => t.complementoPagoId.equals(complementoPagoId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaHora)]))
        .get();
  }

  @override
  Future<ComplementoPagoData> crear({
    required String pagoId,
    required String uuid,
    String? serieFiscal,
    String? folioFiscal,
    required DateTime fechaTimbrado,
    required int montoTotal,
    String? observaciones,
    String? actor,
  }) {
    return _db.transaction(() async {
      final complemento = await _db.into(_db.complementoPago).insertReturning(
            ComplementoPagoCompanion.insert(
              pagoId: pagoId,
              uuid: uuid,
              serieFiscal: Value(serieFiscal),
              folioFiscal: Value(folioFiscal),
              fechaTimbrado: fechaTimbrado,
              montoTotal: montoTotal,
              observaciones: Value(observaciones),
            ),
          );

      await _registrarEvento(
        complementoPagoId: complemento.id,
        tipoEvento: TipoEventoComplementoPago.registrado,
        estadoAnterior: null,
        estadoNuevo: complemento.estatus,
        actor: actor,
        datosRelevantes: {'pagoId': pagoId, 'uuid': uuid, 'montoTotal': montoTotal},
      );

      return complemento;
    });
  }

  @override
  Future<ComplementoPagoData> corregir({
    required String complementoPagoId,
    String? serieFiscal,
    String? folioFiscal,
    DateTime? fechaTimbrado,
    String? observaciones,
    required String motivo,
    String? actor,
  }) {
    return _db.transaction(() async {
      final anterior =
          await (_db.select(_db.complementoPago)..where((t) => t.id.equals(complementoPagoId))).getSingle();

      await (_db.update(_db.complementoPago)..where((t) => t.id.equals(complementoPagoId))).write(
        ComplementoPagoCompanion(
          serieFiscal: serieFiscal == null ? const Value.absent() : Value(serieFiscal),
          folioFiscal: folioFiscal == null ? const Value.absent() : Value(folioFiscal),
          fechaTimbrado: fechaTimbrado == null ? const Value.absent() : Value(fechaTimbrado),
          observaciones: observaciones == null ? const Value.absent() : Value(observaciones),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEvento(
        complementoPagoId: complementoPagoId,
        tipoEvento: TipoEventoComplementoPago.corregido,
        estadoAnterior: anterior.estatus,
        estadoNuevo: anterior.estatus,
        observacion: motivo,
        actor: actor,
        datosRelevantes: {
          'serieFiscalAnterior': anterior.serieFiscal,
          'folioFiscalAnterior': anterior.folioFiscal,
          'fechaTimbradoAnterior': anterior.fechaTimbrado.toIso8601String(),
        },
      );

      return (_db.select(_db.complementoPago)..where((t) => t.id.equals(complementoPagoId))).getSingle();
    });
  }

  @override
  Future<ComplementoPagoData> cancelar({
    required String complementoPagoId,
    required String motivo,
    String? actor,
  }) {
    return _db.transaction(() async {
      final anterior =
          await (_db.select(_db.complementoPago)..where((t) => t.id.equals(complementoPagoId))).getSingle();

      await (_db.update(_db.complementoPago)..where((t) => t.id.equals(complementoPagoId))).write(
        ComplementoPagoCompanion(
          estatus: Value(EstatusComplementoPago.cancelado.name),
          motivoCancelacion: Value(motivo),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEvento(
        complementoPagoId: complementoPagoId,
        tipoEvento: TipoEventoComplementoPago.cancelado,
        estadoAnterior: anterior.estatus,
        estadoNuevo: EstatusComplementoPago.cancelado.name,
        observacion: motivo,
        actor: actor,
      );

      return (_db.select(_db.complementoPago)..where((t) => t.id.equals(complementoPagoId))).getSingle();
    });
  }

  @override
  Future<AttachmentData> adjuntarArchivo({
    required String complementoPagoId,
    required String categoria,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actor,
  }) {
    return _db.transaction(() async {
      final adjunto = await _db.into(_db.attachment).insertReturning(
            AttachmentCompanion.insert(
              id: const Uuid().v4(),
              categoria: Value(categoria),
              originalFileName: originalFileName,
              storedFileName: storedFileName,
              path: path,
              mimeType: mimeType,
              sizeBytes: sizeBytes,
            ),
          );
      await _db.into(_db.complementoPagoAttachment).insert(
            ComplementoPagoAttachmentCompanion.insert(attachmentId: adjunto.id, complementoPagoId: complementoPagoId),
          );

      await _registrarEvento(
        complementoPagoId: complementoPagoId,
        tipoEvento: TipoEventoComplementoPago.archivoAdjuntado,
        estadoAnterior: null,
        estadoNuevo: null,
        actor: actor,
        datosRelevantes: {'categoria': categoria, 'archivoNuevo': originalFileName, 'attachmentId': adjunto.id},
      );

      return adjunto;
    });
  }

  Future<void> _registrarEvento({
    required String complementoPagoId,
    required TipoEventoComplementoPago tipoEvento,
    required String? estadoAnterior,
    required String? estadoNuevo,
    String? observacion,
    String? actor,
    Map<String, Object?>? datosRelevantes,
  }) {
    return _db.into(_db.complementoPagoEvento).insert(
          ComplementoPagoEventoCompanion.insert(
            complementoPagoId: complementoPagoId,
            fechaHora: DateTime.now(),
            tipoEvento: tipoEvento.name,
            estadoAnterior: Value(estadoAnterior),
            estadoNuevo: Value(estadoNuevo),
            observacion: Value(observacion),
            actor: Value(actor),
            datosRelevantes: Value(datosRelevantes == null ? null : jsonEncode(datosRelevantes)),
          ),
        );
  }
}
