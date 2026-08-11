import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/egreso_repository.dart';
import 'package:uuid/uuid.dart';

import '../../domain/repositories/pago_nomina_repository.dart';
import '../tables/nomina_empleado_table.dart' show EstatusPagoNominaEmpleado;
import '../tables/pago_nomina_table.dart' show TipoEventoPagoNomina;

/// Cruza de `nomina` a `finanzas` (mismo criterio que
/// `DocumentoPorEmitirRepositoryImpl` depende de
/// `CuentaPorCobrarRepository`): `crear`/`cancelar` componen el
/// `Egreso` automático vía `EgresoRepository`, nunca escribiendo
/// directo sobre `_db.egreso` — a diferencia de `PagoRepositoryImpl`,
/// que sí escribe directo sobre `_db.ingreso` porque `Pago`/`Ingreso`
/// viven en el mismo dominio (`finanzas`).
class PagoNominaRepositoryImpl implements PagoNominaRepository {
  PagoNominaRepositoryImpl(this._db, this._egresoRepository);

  final AppDatabase _db;
  final EgresoRepository _egresoRepository;
  late final _codigoSecuencia = CodigoSecuenciaService(_db);

  @override
  Future<PagoNominaData?> obtenerPorId(String id) {
    return (_db.select(_db.pagoNomina)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<AplicacionPagoNominaData?> obtenerAplicacionPorId(String id) {
    return (_db.select(_db.aplicacionPagoNomina)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<PagoNominaData>> listarPorNomina(String nominaId) {
    return (_db.select(_db.pagoNomina)
          ..where((t) => t.nominaId.equals(nominaId))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaPago)]))
        .get();
  }

  @override
  Future<List<AplicacionPagoNominaData>> listarAplicacionesPorPagoNomina(String pagoNominaId) {
    return (_db.select(_db.aplicacionPagoNomina)
          ..where((t) => t.pagoNominaId.equals(pagoNominaId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  @override
  Future<List<AplicacionPagoNominaData>> listarAplicacionesPorRenglon(String nominaEmpleadoId) {
    return (_db.select(_db.aplicacionPagoNomina)
          ..where((t) => t.nominaEmpleadoId.equals(nominaEmpleadoId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  @override
  Future<List<PagoNominaData>> listarEnRango({DateTime? rangoInicio, DateTime? rangoFin}) {
    final query = _db.select(_db.pagoNomina)..where((t) => t.estatus.equals('registrado'));
    if (rangoInicio != null) query.where((t) => t.fechaPago.isBiggerOrEqualValue(rangoInicio));
    if (rangoFin != null) query.where((t) => t.fechaPago.isSmallerOrEqualValue(rangoFin));
    query.orderBy([(t) => OrderingTerm.desc(t.fechaPago)]);
    return query.get();
  }

  @override
  Future<int> totalPagadoEnRango({DateTime? rangoInicio, DateTime? rangoFin}) async {
    final query = _db.selectOnly(_db.pagoNomina)
      ..addColumns([_db.pagoNomina.montoTotal.sum()])
      ..where(_db.pagoNomina.estatus.equals('registrado'));
    if (rangoInicio != null) query.where(_db.pagoNomina.fechaPago.isBiggerOrEqualValue(rangoInicio));
    if (rangoFin != null) query.where(_db.pagoNomina.fechaPago.isSmallerOrEqualValue(rangoFin));
    final fila = await query.getSingle();
    return fila.read(_db.pagoNomina.montoTotal.sum()) ?? 0;
  }

  @override
  Future<List<PagoNominaEventoData>> listarEventos(String pagoNominaId) {
    return (_db.select(_db.pagoNominaEvento)
          ..where((t) => t.pagoNominaId.equals(pagoNominaId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaHora)]))
        .get();
  }

  @override
  Future<int> saldoPendientePago(String nominaEmpleadoId) async {
    final renglon = await (_db.select(_db.nominaEmpleado)..where((t) => t.id.equals(nominaEmpleadoId))).getSingle();

    final query = _db.selectOnly(_db.aplicacionPagoNomina)
      ..addColumns([_db.aplicacionPagoNomina.monto.sum()])
      ..where(_db.aplicacionPagoNomina.nominaEmpleadoId.equals(nominaEmpleadoId) &
          _db.aplicacionPagoNomina.estatus.equals('aplicada'));
    final row = await query.getSingle();
    final aplicado = row.read(_db.aplicacionPagoNomina.monto.sum()) ?? 0;

    return renglon.totalAPagar - aplicado;
  }

  @override
  Future<Map<String, int>> totalAplicadoPorRenglon(List<String> nominaEmpleadoIds) async {
    if (nominaEmpleadoIds.isEmpty) return {};
    final query = _db.selectOnly(_db.aplicacionPagoNomina)
      ..addColumns([_db.aplicacionPagoNomina.nominaEmpleadoId, _db.aplicacionPagoNomina.monto.sum()])
      ..where(_db.aplicacionPagoNomina.nominaEmpleadoId.isIn(nominaEmpleadoIds) &
          _db.aplicacionPagoNomina.estatus.equals('aplicada'))
      ..groupBy([_db.aplicacionPagoNomina.nominaEmpleadoId]);
    final filas = await query.get();
    return {
      for (final fila in filas)
        fila.read(_db.aplicacionPagoNomina.nominaEmpleadoId)!: fila.read(_db.aplicacionPagoNomina.monto.sum()) ?? 0,
    };
  }

  EstatusPagoNominaEmpleado _estatusPagoPorSaldo(int saldoPendiente, int totalAPagar) {
    if (saldoPendiente <= 0) return EstatusPagoNominaEmpleado.pagado;
    if (saldoPendiente < totalAPagar) return EstatusPagoNominaEmpleado.parcial;
    return EstatusPagoNominaEmpleado.pendiente;
  }

  /// Sube la Nómina a `pagada` cuando los 4 renglones reportan
  /// `estatusPago == pagado`, o la regresa a `cerrada` si una
  /// cancelación reabrió saldo pendiente — nunca deja una Nómina
  /// marcada `pagada` con dinero real todavía por pagar.
  Future<void> _evaluarNominaPagada(String nominaId) async {
    final renglones = await (_db.select(_db.nominaEmpleado)..where((t) => t.nominaId.equals(nominaId))).get();
    final todosPagados = renglones.isNotEmpty && renglones.every((r) => r.estatusPago == 'pagado');
    final nomina = await (_db.select(_db.nomina)..where((t) => t.id.equals(nominaId))).getSingle();

    if (todosPagados && nomina.estatus == 'cerrada') {
      await (_db.update(_db.nomina)..where((t) => t.id.equals(nominaId))).write(
        NominaCompanion(estatus: const Value('pagada'), updatedAt: Value(DateTime.now())),
      );
    } else if (!todosPagados && nomina.estatus == 'pagada') {
      await (_db.update(_db.nomina)..where((t) => t.id.equals(nominaId))).write(
        NominaCompanion(estatus: const Value('cerrada'), updatedAt: Value(DateTime.now())),
      );
    }
  }

  Future<AplicacionPagoNominaData> _aplicarInterna({
    required String pagoNominaId,
    required String nominaEmpleadoId,
    required int monto,
  }) async {
    final renglon = await (_db.select(_db.nominaEmpleado)..where((t) => t.id.equals(nominaEmpleadoId))).getSingle();
    final saldoAntes = await saldoPendientePago(nominaEmpleadoId);
    final saldoDespues = saldoAntes - monto;

    final aplicacion = await _db.into(_db.aplicacionPagoNomina).insertReturning(
          AplicacionPagoNominaCompanion.insert(
            pagoNominaId: pagoNominaId,
            nominaEmpleadoId: nominaEmpleadoId,
            monto: monto,
            saldoAntes: saldoAntes,
            saldoDespues: saldoDespues,
          ),
        );

    final nuevoEstatus = _estatusPagoPorSaldo(saldoDespues, renglon.totalAPagar);
    await (_db.update(_db.nominaEmpleado)..where((t) => t.id.equals(nominaEmpleadoId))).write(
      NominaEmpleadoCompanion(estatusPago: Value(nuevoEstatus.name), updatedAt: Value(DateTime.now())),
    );

    await _evaluarNominaPagada(renglon.nominaId);

    return aplicacion;
  }

  @override
  Future<PagoNominaData> crear({
    required String folioPagoNomina,
    required String nominaId,
    required DateTime fechaPago,
    required String formaPago,
    String? referencia,
    String? cuentaBancariaOrigen,
    String? observaciones,
    required List<({String nominaEmpleadoId, int monto})> aplicaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final nomina = await (_db.select(_db.nomina)..where((t) => t.id.equals(nominaId))).getSingle();
      final montoTotal = aplicaciones.fold<int>(0, (s, a) => s + a.monto);

      final folioEgreso = await _codigoSecuencia.siguienteCodigo('egreso');
      final egreso = await _egresoRepository.crear(
        folioEgreso: folioEgreso,
        monto: montoTotal,
        fecha: fechaPago,
        cuentaCaja: cuentaBancariaOrigen,
        formaPago: formaPago,
        concepto: 'Pago de Nómina $folioPagoNomina (${nomina.folio})',
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );

      final pagoNomina = await _db.into(_db.pagoNomina).insertReturning(
            PagoNominaCompanion.insert(
              folioPagoNomina: folioPagoNomina,
              nominaId: nominaId,
              egresoId: Value(egreso.id),
              montoTotal: montoTotal,
              fechaPago: fechaPago,
              formaPago: formaPago,
              referencia: Value(referencia),
              cuentaBancariaOrigen: Value(cuentaBancariaOrigen),
              observaciones: Value(observaciones),
            ),
          );

      await _registrarEventoInterno(
        pagoNominaId: pagoNomina.id,
        tipoEvento: TipoEventoPagoNomina.registrado,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'folioPagoNomina': folioPagoNomina,
          'montoTotal': montoTotal,
          'empleados': aplicaciones.length,
        },
      );

      for (final ap in aplicaciones) {
        await _aplicarInterna(pagoNominaId: pagoNomina.id, nominaEmpleadoId: ap.nominaEmpleadoId, monto: ap.monto);
      }

      return pagoNomina;
    });
  }

  @override
  Future<PagoNominaData> corregir({
    required String pagoNominaId,
    DateTime? fechaPago,
    String? formaPago,
    String? referencia,
    String? cuentaBancariaOrigen,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.pagoNomina)..where((t) => t.id.equals(pagoNominaId))).getSingle();

      await (_db.update(_db.pagoNomina)..where((t) => t.id.equals(pagoNominaId))).write(
        PagoNominaCompanion(
          fechaPago: fechaPago == null ? const Value.absent() : Value(fechaPago),
          formaPago: formaPago == null ? const Value.absent() : Value(formaPago),
          referencia: referencia == null ? const Value.absent() : Value(referencia),
          cuentaBancariaOrigen: cuentaBancariaOrigen == null ? const Value.absent() : Value(cuentaBancariaOrigen),
          observaciones: observaciones == null ? const Value.absent() : Value(observaciones),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEventoInterno(
        pagoNominaId: pagoNominaId,
        tipoEvento: TipoEventoPagoNomina.corregido,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'fechaPagoAnterior': anterior.fechaPago.toIso8601String(),
          'formaPagoAnterior': anterior.formaPago,
          'referenciaAnterior': anterior.referencia,
          'cuentaBancariaOrigenAnterior': anterior.cuentaBancariaOrigen,
        },
      );

      return (_db.select(_db.pagoNomina)..where((t) => t.id.equals(pagoNominaId))).getSingle();
    });
  }

  Future<void> _cancelarAplicacionInterna(AplicacionPagoNominaData aplicacion, {required String motivo}) async {
    final renglon =
        await (_db.select(_db.nominaEmpleado)..where((t) => t.id.equals(aplicacion.nominaEmpleadoId))).getSingle();

    await (_db.update(_db.aplicacionPagoNomina)..where((t) => t.id.equals(aplicacion.id))).write(
      AplicacionPagoNominaCompanion(
        estatus: const Value('cancelada'),
        motivoCancelacion: Value(motivo),
        updatedAt: Value(DateTime.now()),
      ),
    );

    final nuevoSaldo = await saldoPendientePago(aplicacion.nominaEmpleadoId);
    final nuevoEstatus = _estatusPagoPorSaldo(nuevoSaldo, renglon.totalAPagar);
    await (_db.update(_db.nominaEmpleado)..where((t) => t.id.equals(aplicacion.nominaEmpleadoId))).write(
      NominaEmpleadoCompanion(estatusPago: Value(nuevoEstatus.name), updatedAt: Value(DateTime.now())),
    );

    await _evaluarNominaPagada(renglon.nominaId);
  }

  @override
  Future<PagoNominaData> cancelar({required String pagoNominaId, required String motivo, String? actorUsuarioId}) {
    return _db.transaction(() async {
      final pagoNomina = await (_db.select(_db.pagoNomina)..where((t) => t.id.equals(pagoNominaId))).getSingle();

      final aplicaciones = await (_db.select(_db.aplicacionPagoNomina)
            ..where((t) => t.pagoNominaId.equals(pagoNominaId) & t.estatus.equals('aplicada')))
          .get();
      for (final aplicacion in aplicaciones) {
        await _cancelarAplicacionInterna(aplicacion, motivo: motivo);
      }

      await (_db.update(_db.pagoNomina)..where((t) => t.id.equals(pagoNominaId))).write(
        PagoNominaCompanion(
          estatus: const Value('cancelado'),
          motivoCancelacion: Value(motivo),
          updatedAt: Value(DateTime.now()),
        ),
      );

      if (pagoNomina.egresoId != null) {
        await _egresoRepository.cancelar(egresoId: pagoNomina.egresoId!, motivo: motivo, actorUsuarioId: actorUsuarioId);
      }

      await _registrarEventoInterno(
        pagoNominaId: pagoNominaId,
        tipoEvento: TipoEventoPagoNomina.cancelado,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
      );

      return (_db.select(_db.pagoNomina)..where((t) => t.id.equals(pagoNominaId))).getSingle();
    });
  }

  @override
  Future<AttachmentData> adjuntarComprobante({
    required String pagoNominaId,
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
      await _db.into(_db.pagoNominaAttachment).insert(
            PagoNominaAttachmentCompanion.insert(attachmentId: adjunto.id, pagoNominaId: pagoNominaId),
          );

      await _registrarEventoInterno(
        pagoNominaId: pagoNominaId,
        tipoEvento: TipoEventoPagoNomina.comprobanteAdjuntado,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'archivoNuevo': originalFileName, 'attachmentId': adjunto.id},
      );

      return adjunto;
    });
  }

  Future<void> _registrarEventoInterno({
    required String pagoNominaId,
    required TipoEventoPagoNomina tipoEvento,
    String? estadoAnterior,
    String? estadoNuevo,
    String? observacion,
    String? actorUsuarioId,
    Map<String, dynamic>? datosRelevantes,
  }) {
    return _db.into(_db.pagoNominaEvento).insert(
          PagoNominaEventoCompanion.insert(
            pagoNominaId: pagoNominaId,
            fechaHora: DateTime.now(),
            tipoEvento: tipoEvento.name,
            estadoAnterior: Value(estadoAnterior),
            estadoNuevo: Value(estadoNuevo),
            observacion: Value(observacion),
            actorUsuarioId: Value(actorUsuarioId),
            datosRelevantes: datosRelevantes == null ? const Value.absent() : Value(jsonEncode(datosRelevantes)),
          ),
        );
  }
}
