import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/ingreso_table.dart';
import 'package:uuid/uuid.dart';

import '../../domain/repositories/ingreso_repository.dart';

class IngresoRepositoryImpl implements IngresoRepository {
  IngresoRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<IngresoData?> obtenerPorId(String id) {
    return (_db.select(_db.ingreso)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<IngresoData?> obtenerPorPagoId(String pagoId) {
    return (_db.select(_db.ingreso)..where((t) => t.pagoId.equals(pagoId))).getSingleOrNull();
  }

  @override
  Future<List<IngresoData>> listar({
    String? estatus,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    DateTime? rangoInicio,
    DateTime? rangoFin,
  }) {
    final query = _db.select(_db.ingreso);
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
  Future<List<IngresoEventoData>> listarEventos(String ingresoId) {
    return (_db.select(_db.ingresoEvento)
          ..where((t) => t.ingresoId.equals(ingresoId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaHora)]))
        .get();
  }

  @override
  Future<IngresoData> crear({
    String? pagoId,
    required String folioIngreso,
    required int monto,
    required DateTime fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    required String formaPago,
    required String concepto,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final ingreso = await _db.into(_db.ingreso).insertReturning(
            IngresoCompanion.insert(
              pagoId: Value(pagoId),
              folioIngreso: folioIngreso,
              monto: monto,
              fecha: fecha,
              categoriaFinancieraId: Value(categoriaFinancieraId),
              servicioId: Value(servicioId),
              sucursalId: Value(sucursalId),
              areaId: Value(areaId),
              cuentaCaja: Value(cuentaCaja),
              formaPago: formaPago,
              concepto: concepto,
              observaciones: Value(observaciones),
            ),
          );

      await _registrarEvento(
        ingresoId: ingreso.id,
        tipoEvento: TipoEventoIngreso.registrado,
        estadoAnterior: null,
        estadoNuevo: ingreso.estatus,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'folioIngreso': folioIngreso, 'monto': monto, 'pagoId': pagoId},
      );

      return ingreso;
    });
  }

  @override
  Future<IngresoData> corregir({
    required String ingresoId,
    DateTime? fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    String? formaPago,
    String? concepto,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.ingreso)..where((t) => t.id.equals(ingresoId))).getSingle();

      await (_db.update(_db.ingreso)..where((t) => t.id.equals(ingresoId))).write(
        IngresoCompanion(
          fecha: fecha == null ? const Value.absent() : Value(fecha),
          categoriaFinancieraId: categoriaFinancieraId == null ? const Value.absent() : Value(categoriaFinancieraId),
          servicioId: servicioId == null ? const Value.absent() : Value(servicioId),
          sucursalId: sucursalId == null ? const Value.absent() : Value(sucursalId),
          areaId: areaId == null ? const Value.absent() : Value(areaId),
          cuentaCaja: cuentaCaja == null ? const Value.absent() : Value(cuentaCaja),
          formaPago: formaPago == null ? const Value.absent() : Value(formaPago),
          concepto: concepto == null ? const Value.absent() : Value(concepto),
          observaciones: observaciones == null ? const Value.absent() : Value(observaciones),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEvento(
        ingresoId: ingresoId,
        tipoEvento: TipoEventoIngreso.corregido,
        estadoAnterior: anterior.estatus,
        estadoNuevo: anterior.estatus,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'fechaAnterior': anterior.fecha.toIso8601String(),
          'conceptoAnterior': anterior.concepto,
        },
      );

      return (_db.select(_db.ingreso)..where((t) => t.id.equals(ingresoId))).getSingle();
    });
  }

  @override
  Future<IngresoData> cancelar({
    required String ingresoId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.ingreso)..where((t) => t.id.equals(ingresoId))).getSingle();

      await (_db.update(_db.ingreso)..where((t) => t.id.equals(ingresoId))).write(
        IngresoCompanion(
          estatus: Value(EstatusIngreso.cancelado.name),
          motivoCancelacion: Value(motivo),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEvento(
        ingresoId: ingresoId,
        tipoEvento: TipoEventoIngreso.cancelado,
        estadoAnterior: anterior.estatus,
        estadoNuevo: EstatusIngreso.cancelado.name,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
      );

      return (_db.select(_db.ingreso)..where((t) => t.id.equals(ingresoId))).getSingle();
    });
  }

  @override
  Future<AttachmentData> adjuntarComprobante({
    required String ingresoId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actorUsuarioId,
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
      await _db.into(_db.ingresoAttachment).insert(
            IngresoAttachmentCompanion.insert(attachmentId: adjunto.id, ingresoId: ingresoId),
          );

      await _registrarEvento(
        ingresoId: ingresoId,
        tipoEvento: TipoEventoIngreso.comprobanteAdjuntado,
        estadoAnterior: null,
        estadoNuevo: null,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'archivoNuevo': originalFileName, 'attachmentId': adjunto.id},
      );

      return adjunto;
    });
  }

  @override
  Future<int> totalIngresos({DateTime? rangoInicio, DateTime? rangoFin}) async {
    final query = _db.selectOnly(_db.ingreso)
      ..addColumns([_db.ingreso.monto.sum()])
      ..where(_db.ingreso.estatus.equals(EstatusIngreso.registrado.name));
    if (rangoInicio != null) query.where(_db.ingreso.fecha.isBiggerOrEqualValue(rangoInicio));
    if (rangoFin != null) query.where(_db.ingreso.fecha.isSmallerOrEqualValue(rangoFin));
    final fila = await query.getSingle();
    return fila.read(_db.ingreso.monto.sum()) ?? 0;
  }

  Future<void> _registrarEvento({
    required String ingresoId,
    required TipoEventoIngreso tipoEvento,
    required String? estadoAnterior,
    required String? estadoNuevo,
    String? observacion,
    String? actorUsuarioId,
    Map<String, Object?>? datosRelevantes,
  }) {
    return _db.into(_db.ingresoEvento).insert(
          IngresoEventoCompanion.insert(
            ingresoId: ingresoId,
            fechaHora: DateTime.now(),
            tipoEvento: tipoEvento.name,
            estadoAnterior: Value(estadoAnterior),
            estadoNuevo: Value(estadoNuevo),
            observacion: Value(observacion),
            actorUsuarioId: Value(actorUsuarioId),
            datosRelevantes: Value(datosRelevantes == null ? null : jsonEncode(datosRelevantes)),
          ),
        );
  }
}
