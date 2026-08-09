import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/egreso_table.dart';
import 'package:uuid/uuid.dart';

import '../../domain/repositories/egreso_repository.dart';

class EgresoRepositoryImpl implements EgresoRepository {
  EgresoRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<EgresoData?> obtenerPorId(String id) {
    return (_db.select(_db.egreso)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<EgresoData>> listar({
    String? estatus,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    DateTime? rangoInicio,
    DateTime? rangoFin,
  }) {
    final query = _db.select(_db.egreso);
    if (estatus != null) query.where((t) => t.estatus.equals(estatus));
    if (categoriaFinancieraId != null) query.where((t) => t.categoriaFinancieraId.equals(categoriaFinancieraId));
    if (servicioId != null) query.where((t) => t.servicioId.equals(servicioId));
    if (sucursalId != null) query.where((t) => t.sucursalId.equals(sucursalId));
    if (areaId != null) query.where((t) => t.areaId.equals(areaId));
    if (rangoInicio != null) query.where((t) => t.fecha.isBiggerOrEqualValue(rangoInicio));
    if (rangoFin != null) query.where((t) => t.fecha.isSmallerOrEqualValue(rangoFin));
    query.orderBy([(t) => OrderingTerm.desc(t.fecha)]);
    return query.get();
  }

  @override
  Future<List<EgresoEventoData>> listarEventos(String egresoId) {
    return (_db.select(_db.egresoEvento)
          ..where((t) => t.egresoId.equals(egresoId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaHora)]))
        .get();
  }

  @override
  Future<EgresoData> crear({
    required String folioEgreso,
    required int monto,
    required DateTime fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    required String formaPago,
    String? beneficiario,
    required String concepto,
    String? observaciones,
    String? actor,
  }) {
    return _db.transaction(() async {
      final egreso = await _db.into(_db.egreso).insertReturning(
            EgresoCompanion.insert(
              folioEgreso: folioEgreso,
              monto: monto,
              fecha: fecha,
              categoriaFinancieraId: Value(categoriaFinancieraId),
              servicioId: Value(servicioId),
              sucursalId: Value(sucursalId),
              areaId: Value(areaId),
              cuentaCaja: Value(cuentaCaja),
              formaPago: formaPago,
              beneficiario: Value(beneficiario),
              concepto: concepto,
              observaciones: Value(observaciones),
            ),
          );

      await _registrarEvento(
        egresoId: egreso.id,
        tipoEvento: TipoEventoEgreso.registrado,
        estadoAnterior: null,
        estadoNuevo: egreso.estatus,
        actor: actor,
        datosRelevantes: {'folioEgreso': folioEgreso, 'monto': monto},
      );

      return egreso;
    });
  }

  @override
  Future<EgresoData> corregir({
    required String egresoId,
    DateTime? fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    String? formaPago,
    String? beneficiario,
    String? concepto,
    String? observaciones,
    required String motivo,
    String? actor,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.egreso)..where((t) => t.id.equals(egresoId))).getSingle();

      await (_db.update(_db.egreso)..where((t) => t.id.equals(egresoId))).write(
        EgresoCompanion(
          fecha: fecha == null ? const Value.absent() : Value(fecha),
          categoriaFinancieraId: categoriaFinancieraId == null ? const Value.absent() : Value(categoriaFinancieraId),
          servicioId: servicioId == null ? const Value.absent() : Value(servicioId),
          sucursalId: sucursalId == null ? const Value.absent() : Value(sucursalId),
          areaId: areaId == null ? const Value.absent() : Value(areaId),
          cuentaCaja: cuentaCaja == null ? const Value.absent() : Value(cuentaCaja),
          formaPago: formaPago == null ? const Value.absent() : Value(formaPago),
          beneficiario: beneficiario == null ? const Value.absent() : Value(beneficiario),
          concepto: concepto == null ? const Value.absent() : Value(concepto),
          observaciones: observaciones == null ? const Value.absent() : Value(observaciones),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEvento(
        egresoId: egresoId,
        tipoEvento: TipoEventoEgreso.corregido,
        estadoAnterior: anterior.estatus,
        estadoNuevo: anterior.estatus,
        observacion: motivo,
        actor: actor,
        datosRelevantes: {
          'fechaAnterior': anterior.fecha.toIso8601String(),
          'conceptoAnterior': anterior.concepto,
        },
      );

      return (_db.select(_db.egreso)..where((t) => t.id.equals(egresoId))).getSingle();
    });
  }

  @override
  Future<EgresoData> cancelar({
    required String egresoId,
    required String motivo,
    String? actor,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.egreso)..where((t) => t.id.equals(egresoId))).getSingle();

      await (_db.update(_db.egreso)..where((t) => t.id.equals(egresoId))).write(
        EgresoCompanion(
          estatus: Value(EstatusEgreso.cancelado.name),
          motivoCancelacion: Value(motivo),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEvento(
        egresoId: egresoId,
        tipoEvento: TipoEventoEgreso.cancelado,
        estadoAnterior: anterior.estatus,
        estadoNuevo: EstatusEgreso.cancelado.name,
        observacion: motivo,
        actor: actor,
      );

      return (_db.select(_db.egreso)..where((t) => t.id.equals(egresoId))).getSingle();
    });
  }

  @override
  Future<AttachmentData> adjuntarComprobante({
    required String egresoId,
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
              categoria: const Value('comprobante'),
              originalFileName: originalFileName,
              storedFileName: storedFileName,
              path: path,
              mimeType: mimeType,
              sizeBytes: sizeBytes,
            ),
          );
      await _db.into(_db.egresoAttachment).insert(
            EgresoAttachmentCompanion.insert(attachmentId: adjunto.id, egresoId: egresoId),
          );

      await _registrarEvento(
        egresoId: egresoId,
        tipoEvento: TipoEventoEgreso.comprobanteAdjuntado,
        estadoAnterior: null,
        estadoNuevo: null,
        actor: actor,
        datosRelevantes: {'archivoNuevo': originalFileName, 'attachmentId': adjunto.id},
      );

      return adjunto;
    });
  }

  @override
  Future<int> totalEgresos({DateTime? rangoInicio, DateTime? rangoFin}) async {
    final query = _db.selectOnly(_db.egreso)
      ..addColumns([_db.egreso.monto.sum()])
      ..where(_db.egreso.estatus.equals(EstatusEgreso.registrado.name));
    if (rangoInicio != null) query.where(_db.egreso.fecha.isBiggerOrEqualValue(rangoInicio));
    if (rangoFin != null) query.where(_db.egreso.fecha.isSmallerOrEqualValue(rangoFin));
    final fila = await query.getSingle();
    return fila.read(_db.egreso.monto.sum()) ?? 0;
  }

  Future<void> _registrarEvento({
    required String egresoId,
    required TipoEventoEgreso tipoEvento,
    required String? estadoAnterior,
    required String? estadoNuevo,
    String? observacion,
    String? actor,
    Map<String, Object?>? datosRelevantes,
  }) {
    return _db.into(_db.egresoEvento).insert(
          EgresoEventoCompanion.insert(
            egresoId: egresoId,
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
