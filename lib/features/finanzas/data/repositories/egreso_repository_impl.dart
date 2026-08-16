import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/egreso_table.dart';
import 'package:uuid/uuid.dart';

import '../../domain/repositories/egreso_repository.dart';
import '../../domain/usecases/eliminar_egreso_fisicamente_usecase.dart';

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
    String? actorUsuarioId,
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
        actorUsuarioId: actorUsuarioId,
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
    String? actorUsuarioId,
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
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'fechaAnterior': anterior.fecha.toIso8601String(),
          'conceptoAnterior': anterior.concepto,
        },
      );

      return (_db.select(_db.egreso)..where((t) => t.id.equals(egresoId))).getSingle();
    });
  }

  @override
  Future<EgresoData> corregirMonto({
    required String egresoId,
    required int nuevoMonto,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.egreso)..where((t) => t.id.equals(egresoId))).getSingle();

      await (_db.update(_db.egreso)..where((t) => t.id.equals(egresoId))).write(
        EgresoCompanion(monto: Value(nuevoMonto), updatedAt: Value(DateTime.now())),
      );

      await _registrarEvento(
        egresoId: egresoId,
        tipoEvento: TipoEventoEgreso.corregido,
        estadoAnterior: anterior.estatus,
        estadoNuevo: anterior.estatus,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'montoAnterior': anterior.monto, 'montoNuevo': nuevoMonto},
      );

      return (_db.select(_db.egreso)..where((t) => t.id.equals(egresoId))).getSingle();
    });
  }

  @override
  Future<EgresoData> cancelar({
    required String egresoId,
    required String motivo,
    String? actorUsuarioId,
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
        actorUsuarioId: actorUsuarioId,
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
      await _db.into(_db.egresoAttachment).insert(
            EgresoAttachmentCompanion.insert(attachmentId: adjunto.id, egresoId: egresoId),
          );

      await _registrarEvento(
        egresoId: egresoId,
        tipoEvento: TipoEventoEgreso.comprobanteAdjuntado,
        estadoAnterior: null,
        estadoNuevo: null,
        actorUsuarioId: actorUsuarioId,
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

  @override
  Future<Map<String?, int>> totalPorCategoria({DateTime? rangoInicio, DateTime? rangoFin}) async {
    final query = _db.selectOnly(_db.egreso)
      ..addColumns([_db.egreso.categoriaFinancieraId, _db.egreso.monto.sum()])
      ..where(_db.egreso.estatus.equals(EstatusEgreso.registrado.name))
      ..groupBy([_db.egreso.categoriaFinancieraId]);
    if (rangoInicio != null) query.where(_db.egreso.fecha.isBiggerOrEqualValue(rangoInicio));
    if (rangoFin != null) query.where(_db.egreso.fecha.isSmallerOrEqualValue(rangoFin));
    final filas = await query.get();
    return {
      for (final fila in filas)
        fila.read(_db.egreso.categoriaFinancieraId): fila.read(_db.egreso.monto.sum()) ?? 0,
    };
  }

  /// Único origen automático real (Etapa 15): `Compra.egresoId` y
  /// `PagoNomina.egresoId` (ambas `onDelete: restrict`, ya lo
  /// impedirían a nivel SQLite) — se verifican aquí primero para dar un
  /// mensaje específico con el folio real, nunca una excepción SQL
  /// cruda. `Egreso` no guarda su propio origen; se infiere por
  /// relación inversa, la única fuente determinista real.
  @override
  Future<ResumenEliminacionEgreso> obtenerResumenEliminacionFisica(String egresoId) async {
    final egreso = await obtenerPorId(egresoId);
    if (egreso == null) return const ResumenEliminacionEgreso(existe: false);

    final compra = await (_db.select(_db.compra)..where((t) => t.egresoId.equals(egresoId))).getSingleOrNull();
    if (compra != null) {
      return ResumenEliminacionEgreso(
        existe: true,
        detalleBloqueo:
            'Este Egreso fue generado por la Compra ${compra.folioCompra}. Corrija o elimine la Compra desde su expediente.',
      );
    }

    final pagoNomina =
        await (_db.select(_db.pagoNomina)..where((t) => t.egresoId.equals(egresoId))).getSingleOrNull();
    if (pagoNomina != null) {
      return ResumenEliminacionEgreso(
        existe: true,
        detalleBloqueo:
            'Este Egreso pertenece al Pago de Nómina ${pagoNomina.folioPagoNomina} y no puede eliminarse de forma independiente.',
      );
    }

    return const ResumenEliminacionEgreso(existe: true);
  }

  /// Eliminación física extraordinaria (Etapa 15) — el único bloqueador
  /// real es que el Egreso haya sido generado automáticamente por una
  /// Compra o un Pago de Nómina (`obtenerResumenEliminacionFisica`); el
  /// estatus (`registrado`/`cancelado`) nunca bloquea por sí solo — un
  /// Egreso manual cancelado (captura de prueba) es el caso elegible
  /// típico. Los comprobantes (`EgresoAttachment`) se limpian
  /// explícitamente en la misma transacción, nunca vía `CASCADE`
  /// indiscriminado: son solo soporte documental, no una dependencia
  /// financiera real como `Compra`/`PagoNomina`.
  @override
  Future<EliminarEgresoFisicamenteResultado> eliminarFisicamente({
    required String egresoId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final egresoInicial = await obtenerPorId(egresoId);
    if (egresoInicial == null) return EliminarEgresoFisicamenteNoExiste();

    final resumen = await obtenerResumenEliminacionFisica(egresoId);
    if (resumen.bloqueado) {
      return EliminarEgresoFisicamenteTieneDependencias(resumen.detalleBloqueo!);
    }

    final adjuntosQuery = _db.select(_db.attachment).join([
      innerJoin(_db.egresoAttachment, _db.egresoAttachment.attachmentId.equalsExp(_db.attachment.id)),
    ])
      ..where(_db.egresoAttachment.egresoId.equals(egresoId));
    final adjuntos = await adjuntosQuery.map((row) => row.readTable(_db.attachment)).get();
    final eventos = await listarEventos(egresoId);

    await _db.transaction(() async {
      final snapshot = <String, Object?>{
        'egreso': egresoInicial.toJson(),
        'eventos': [for (final e in eventos) e.toJson()],
        'adjuntos': [for (final a in adjuntos) a.toJson()],
      };

      await (_db.delete(_db.egresoAttachment)..where((t) => t.egresoId.equals(egresoId))).go();
      for (final adjunto in adjuntos) {
        await (_db.delete(_db.attachment)..where((t) => t.id.equals(adjunto.id))).go();
      }

      await _db.into(_db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'egreso',
              entidadIdOriginal: egresoId,
              fechaHora: DateTime.now(),
              motivo: motivo,
              snapshotJson: jsonEncode(snapshot),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );
      await (_db.delete(_db.egreso)..where((t) => t.id.equals(egresoId))).go();
    });

    return EliminarEgresoFisicamenteExitoso();
  }

  Future<void> _registrarEvento({
    required String egresoId,
    required TipoEventoEgreso tipoEvento,
    required String? estadoAnterior,
    required String? estadoNuevo,
    String? observacion,
    String? actorUsuarioId,
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
            actorUsuarioId: Value(actorUsuarioId),
            datosRelevantes: Value(datosRelevantes == null ? null : jsonEncode(datosRelevantes)),
          ),
        );
  }
}
