import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/ingreso_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';
import 'package:uuid/uuid.dart';

import '../../domain/repositories/pago_repository.dart';

/// **Nota de arquitectura:** a diferencia de
/// `DocumentoPorEmitirRepositoryImpl` (que depende de
/// `CuentaPorCobrarRepository` porque cruza de `organizacion` a
/// `finanzas`), este repositorio escribe directamente sobre
/// `_db.cuentaPorCobrar`/`_db.cuentaPorCobrarEvento` sin pasar por la
/// interfaz `CuentaPorCobrarRepository` — `Pago` y `CuentaPorCobrar`
/// viven en el mismo dominio (`finanzas`), no hay frontera de feature
/// que cruzar.
///
/// Desde la Etapa 4K.1, `_crear`/`cancelar` componen también el
/// `Ingreso` automático de este Pago (mismo criterio de "misma
/// transacción lógica" que ya rige CxC/Complemento) escribiendo
/// directo sobre `_db.ingreso`/`_db.ingresoEvento` — Resolución 4 de
/// Marlon, explícita: mantener la composición aquí por ahora. **Si
/// esta cadena de composiciones (CxC → Complemento → Ingreso) sigue
/// creciendo en etapas futuras, extraerla a un servicio de aplicación
/// dedicado no rompería el dominio** — las firmas públicas de
/// `PagoRepository` no cambiarían, solo la implementación interna.
class PagoRepositoryImpl implements PagoRepository {
  PagoRepositoryImpl(this._db);

  final AppDatabase _db;
  late final _codigoSecuencia = CodigoSecuenciaService(_db);

  @override
  Future<PagoData?> obtenerPorId(String id) {
    return (_db.select(_db.pago)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<AplicacionPagoData?> obtenerAplicacionPorId(String id) {
    return (_db.select(_db.aplicacionPago)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<PagoData>> listar({
    String? clienteId,
    String? estatus,
    String? formaPago,
    DateTime? rangoInicio,
    DateTime? rangoFin,
  }) {
    final query = _db.select(_db.pago);
    if (clienteId != null) query.where((t) => t.clienteId.equals(clienteId));
    if (estatus != null) query.where((t) => t.estatus.equals(estatus));
    if (formaPago != null) query.where((t) => t.formaPago.equals(formaPago));
    if (rangoInicio != null) query.where((t) => t.fechaPago.isBiggerOrEqualValue(rangoInicio));
    if (rangoFin != null) query.where((t) => t.fechaPago.isSmallerOrEqualValue(rangoFin));
    query.orderBy([(t) => OrderingTerm.desc(t.fechaPago)]);
    return query.get();
  }

  @override
  Future<List<AplicacionPagoData>> listarAplicacionesPorPago(String pagoId) {
    return (_db.select(_db.aplicacionPago)
          ..where((t) => t.pagoId.equals(pagoId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  @override
  Future<List<AplicacionPagoData>> listarAplicacionesPorCuenta(String cuentaPorCobrarId) {
    return (_db.select(_db.aplicacionPago)
          ..where((t) => t.cuentaPorCobrarId.equals(cuentaPorCobrarId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  @override
  Future<List<PagoEventoData>> listarEventos(String pagoId) {
    return (_db.select(_db.pagoEvento)
          ..where((t) => t.pagoId.equals(pagoId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaHora)]))
        .get();
  }

  @override
  Future<PagoData> crear({
    required String folioPago,
    required String clienteId,
    required int montoTotal,
    required DateTime fechaPago,
    required String formaPago,
    String? referencia,
    String? bancoOrigen,
    String? cuentaBancariaDestino,
    String? observaciones,
    String? actor,
  }) {
    return _db.transaction(() => _crear(
          folioPago: folioPago,
          clienteId: clienteId,
          montoTotal: montoTotal,
          fechaPago: fechaPago,
          formaPago: formaPago,
          referencia: referencia,
          bancoOrigen: bancoOrigen,
          cuentaBancariaDestino: cuentaBancariaDestino,
          observaciones: observaciones,
          actor: actor,
        ));
  }

  Future<PagoData> _crear({
    required String folioPago,
    required String clienteId,
    required int montoTotal,
    required DateTime fechaPago,
    required String formaPago,
    String? referencia,
    String? bancoOrigen,
    String? cuentaBancariaDestino,
    String? observaciones,
    String? actor,
  }) async {
    final pago = await _db.into(_db.pago).insertReturning(
          PagoCompanion.insert(
            folioPago: folioPago,
            clienteId: clienteId,
            montoTotal: montoTotal,
            fechaPago: fechaPago,
            formaPago: formaPago,
            referencia: Value(referencia),
            bancoOrigen: Value(bancoOrigen),
            cuentaBancariaDestino: Value(cuentaBancariaDestino),
            observaciones: Value(observaciones),
          ),
        );

    await _registrarEventoPago(
      pagoId: pago.id,
      tipoEvento: TipoEventoPago.registrado,
      estadoAnterior: null,
      estadoNuevo: pago.estatus,
      actor: actor,
      datosRelevantes: {'folioPago': folioPago, 'montoTotal': montoTotal},
    );

    await _crearIngresoAutomatico(pago, actor: actor);

    return pago;
  }

  /// Ingreso reconocido en la misma transacción que el Pago (Etapa
  /// 4K.1, Resolución 3 de Marlon: confirmado, siempre automático) —
  /// el dinero se reconoce como ingreso cuando se recibe (criterio de
  /// caja), no cuando se aplica a una Cuenta por cobrar, así que corre
  /// aquí, no en `_aplicar`. Relación 1:1 con el Pago, mismo criterio
  /// que `ComplementoPago`.
  Future<void> _crearIngresoAutomatico(PagoData pago, {String? actor}) async {
    final folioIngreso = await _codigoSecuencia.siguienteCodigo('ingreso');
    final ingreso = await _db.into(_db.ingreso).insertReturning(
          IngresoCompanion.insert(
            pagoId: Value(pago.id),
            folioIngreso: folioIngreso,
            monto: pago.montoTotal,
            fecha: pago.fechaPago,
            cuentaCaja: Value(pago.cuentaBancariaDestino),
            formaPago: pago.formaPago,
            concepto: 'Pago ${pago.folioPago}',
          ),
        );

    await _db.into(_db.ingresoEvento).insert(
          IngresoEventoCompanion.insert(
            ingresoId: ingreso.id,
            fechaHora: DateTime.now(),
            tipoEvento: TipoEventoIngreso.registrado.name,
            estadoNuevo: Value(ingreso.estatus),
            actor: Value(actor),
            datosRelevantes: Value(jsonEncode({'folioIngreso': folioIngreso, 'pagoId': pago.id})),
          ),
        );
  }

  /// Reversión del `_crearIngresoAutomatico` correspondiente — llamada
  /// desde `cancelar()`, nunca deja un Ingreso vigente para un Pago ya
  /// cancelado.
  Future<void> _cancelarIngresoAutomatico(String pagoId, {required String motivo, String? actor}) async {
    final ingreso = await (_db.select(_db.ingreso)..where((t) => t.pagoId.equals(pagoId))).getSingleOrNull();
    if (ingreso == null || EstatusIngreso.values.byName(ingreso.estatus) == EstatusIngreso.cancelado) return;

    await (_db.update(_db.ingreso)..where((t) => t.id.equals(ingreso.id))).write(
      IngresoCompanion(
        estatus: Value(EstatusIngreso.cancelado.name),
        motivoCancelacion: Value(motivo),
        updatedAt: Value(DateTime.now()),
      ),
    );

    await _db.into(_db.ingresoEvento).insert(
          IngresoEventoCompanion.insert(
            ingresoId: ingreso.id,
            fechaHora: DateTime.now(),
            tipoEvento: TipoEventoIngreso.cancelado.name,
            estadoAnterior: Value(ingreso.estatus),
            estadoNuevo: Value(EstatusIngreso.cancelado.name),
            observacion: Value(motivo),
            actor: Value(actor),
          ),
        );
  }

  @override
  Future<AplicacionPagoData> aplicar({
    required String pagoId,
    required String cuentaPorCobrarId,
    required int monto,
    String? actor,
  }) {
    return _db.transaction(
      () => _aplicar(pagoId: pagoId, cuentaPorCobrarId: cuentaPorCobrarId, monto: monto, actor: actor),
    );
  }

  Future<AplicacionPagoData> _aplicar({
    required String pagoId,
    required String cuentaPorCobrarId,
    required int monto,
    String? actor,
  }) async {
    final pago = await (_db.select(_db.pago)..where((t) => t.id.equals(pagoId))).getSingle();
    final cuenta =
        await (_db.select(_db.cuentaPorCobrar)..where((t) => t.id.equals(cuentaPorCobrarId))).getSingle();

    final saldoAntes = cuenta.saldoPendiente;
    final saldoDespues = saldoAntes - monto;

    final aplicacion = await _db.into(_db.aplicacionPago).insertReturning(
          AplicacionPagoCompanion.insert(
            pagoId: pagoId,
            cuentaPorCobrarId: cuentaPorCobrarId,
            monto: monto,
            saldoAntes: saldoAntes,
            saldoDespues: saldoDespues,
          ),
        );

    await (_db.update(_db.pago)..where((t) => t.id.equals(pagoId))).write(
      PagoCompanion(
        montoAplicado: Value(pago.montoAplicado + monto),
        updatedAt: Value(DateTime.now()),
      ),
    );

    final nuevoEstatusCuenta = _estatusCuentaPorSaldo(saldoDespues, cuenta.saldoOriginal);
    await (_db.update(_db.cuentaPorCobrar)..where((t) => t.id.equals(cuentaPorCobrarId))).write(
      CuentaPorCobrarCompanion(
        saldoPendiente: Value(saldoDespues),
        estatus: Value(nuevoEstatusCuenta.name),
        updatedAt: Value(DateTime.now()),
      ),
    );

    await _registrarEventoCuenta(
      cuentaPorCobrarId: cuentaPorCobrarId,
      tipoEvento: TipoEventoCuentaPorCobrar.pagoAplicado,
      estadoAnterior: cuenta.estatus,
      estadoNuevo: nuevoEstatusCuenta.name,
      actor: actor,
      datosRelevantes: {
        'pagoId': pagoId,
        'aplicacionPagoId': aplicacion.id,
        'monto': monto,
        'saldoAntes': saldoAntes,
        'saldoDespues': saldoDespues,
      },
    );

    return aplicacion;
  }

  @override
  Future<({PagoData pago, AplicacionPagoData aplicacion})> crearAplicado({
    required String folioPago,
    required String clienteId,
    required int montoTotal,
    required DateTime fechaPago,
    required String formaPago,
    required String cuentaPorCobrarId,
    String? referencia,
    String? bancoOrigen,
    String? cuentaBancariaDestino,
    String? observaciones,
    String? actor,
  }) {
    return _db.transaction(() async {
      final pago = await _crear(
        folioPago: folioPago,
        clienteId: clienteId,
        montoTotal: montoTotal,
        fechaPago: fechaPago,
        formaPago: formaPago,
        referencia: referencia,
        bancoOrigen: bancoOrigen,
        cuentaBancariaDestino: cuentaBancariaDestino,
        observaciones: observaciones,
        actor: actor,
      );
      final aplicacion = await _aplicar(
        pagoId: pago.id,
        cuentaPorCobrarId: cuentaPorCobrarId,
        monto: montoTotal,
        actor: actor,
      );
      // `pago` es el snapshot de justo después de `_crear` (con
      // `montoAplicado == 0`) — `_aplicar` ya actualizó la fila real,
      // así que se relee para devolver el estado verdadero, no el
      // stale.
      final pagoActualizado = await (_db.select(_db.pago)..where((t) => t.id.equals(pago.id))).getSingle();
      return (pago: pagoActualizado, aplicacion: aplicacion);
    });
  }

  @override
  Future<PagoData> corregir({
    required String pagoId,
    DateTime? fechaPago,
    String? formaPago,
    String? referencia,
    String? bancoOrigen,
    String? cuentaBancariaDestino,
    String? observaciones,
    required String motivo,
    String? actor,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.pago)..where((t) => t.id.equals(pagoId))).getSingle();

      await (_db.update(_db.pago)..where((t) => t.id.equals(pagoId))).write(
        PagoCompanion(
          fechaPago: fechaPago == null ? const Value.absent() : Value(fechaPago),
          formaPago: formaPago == null ? const Value.absent() : Value(formaPago),
          referencia: referencia == null ? const Value.absent() : Value(referencia),
          bancoOrigen: bancoOrigen == null ? const Value.absent() : Value(bancoOrigen),
          cuentaBancariaDestino: cuentaBancariaDestino == null ? const Value.absent() : Value(cuentaBancariaDestino),
          observaciones: observaciones == null ? const Value.absent() : Value(observaciones),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEventoPago(
        pagoId: pagoId,
        tipoEvento: TipoEventoPago.corregido,
        estadoAnterior: anterior.estatus,
        estadoNuevo: anterior.estatus,
        observacion: motivo,
        actor: actor,
        datosRelevantes: {
          'fechaPagoAnterior': anterior.fechaPago.toIso8601String(),
          'formaPagoAnterior': anterior.formaPago,
          'referenciaAnterior': anterior.referencia,
          'bancoOrigenAnterior': anterior.bancoOrigen,
          'cuentaBancariaDestinoAnterior': anterior.cuentaBancariaDestino,
        },
      );

      return (_db.select(_db.pago)..where((t) => t.id.equals(pagoId))).getSingle();
    });
  }

  @override
  Future<AplicacionPagoData> cancelarAplicacion({
    required String aplicacionPagoId,
    required String motivo,
    String? actor,
  }) {
    return _db.transaction(() async {
      final aplicacion =
          await (_db.select(_db.aplicacionPago)..where((t) => t.id.equals(aplicacionPagoId))).getSingle();
      return _cancelarAplicacionInterna(aplicacion, motivo: motivo, actor: actor);
    });
  }

  /// Reversión compartida por `cancelarAplicacion` y `cancelar` (que
  /// cancela varias a la vez) — nunca se llama fuera de una
  /// transacción ya abierta.
  Future<AplicacionPagoData> _cancelarAplicacionInterna(
    AplicacionPagoData aplicacion, {
    required String motivo,
    String? actor,
  }) async {
    final cuenta =
        await (_db.select(_db.cuentaPorCobrar)..where((t) => t.id.equals(aplicacion.cuentaPorCobrarId))).getSingle();
    final pago = await (_db.select(_db.pago)..where((t) => t.id.equals(aplicacion.pagoId))).getSingle();

    final saldoRevertido = cuenta.saldoPendiente + aplicacion.monto;
    final nuevoEstatusCuenta = _estatusCuentaPorSaldo(saldoRevertido, cuenta.saldoOriginal);

    await (_db.update(_db.cuentaPorCobrar)..where((t) => t.id.equals(cuenta.id))).write(
      CuentaPorCobrarCompanion(
        saldoPendiente: Value(saldoRevertido),
        estatus: Value(nuevoEstatusCuenta.name),
        updatedAt: Value(DateTime.now()),
      ),
    );

    await (_db.update(_db.pago)..where((t) => t.id.equals(pago.id))).write(
      PagoCompanion(
        montoAplicado: Value(pago.montoAplicado - aplicacion.monto),
        updatedAt: Value(DateTime.now()),
      ),
    );

    final aplicacionCancelada = await (_db.update(_db.aplicacionPago)..where((t) => t.id.equals(aplicacion.id)))
        .writeReturning(
      AplicacionPagoCompanion(
        estatus: Value(EstatusAplicacionPago.cancelada.name),
        motivoCancelacion: Value(motivo),
        updatedAt: Value(DateTime.now()),
      ),
    );

    await _registrarEventoCuenta(
      cuentaPorCobrarId: cuenta.id,
      tipoEvento: TipoEventoCuentaPorCobrar.pagoAplicacionCancelada,
      estadoAnterior: cuenta.estatus,
      estadoNuevo: nuevoEstatusCuenta.name,
      observacion: motivo,
      actor: actor,
      datosRelevantes: {
        'pagoId': pago.id,
        'aplicacionPagoId': aplicacion.id,
        'monto': aplicacion.monto,
        'saldoRevertido': saldoRevertido,
      },
    );

    return aplicacionCancelada.single;
  }

  @override
  Future<PagoData> cancelar({
    required String pagoId,
    required String motivo,
    String? actor,
  }) {
    return _db.transaction(() async {
      final pago = await (_db.select(_db.pago)..where((t) => t.id.equals(pagoId))).getSingle();

      final aplicacionesActivas = await (_db.select(_db.aplicacionPago)
            ..where((t) => t.pagoId.equals(pagoId) & t.estatus.equals(EstatusAplicacionPago.aplicada.name)))
          .get();

      for (final aplicacion in aplicacionesActivas) {
        await _cancelarAplicacionInterna(
          aplicacion,
          motivo: 'Cancelación en cascada del Pago $pagoId.',
          actor: actor,
        );
      }

      await (_db.update(_db.pago)..where((t) => t.id.equals(pagoId))).write(
        PagoCompanion(
          estatus: Value(EstatusPago.cancelado.name),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEventoPago(
        pagoId: pagoId,
        tipoEvento: TipoEventoPago.cancelado,
        estadoAnterior: pago.estatus,
        estadoNuevo: EstatusPago.cancelado.name,
        observacion: motivo,
        actor: actor,
        datosRelevantes: {'aplicacionesCanceladas': aplicacionesActivas.length},
      );

      await _cancelarIngresoAutomatico(pagoId, motivo: motivo, actor: actor);

      return (_db.select(_db.pago)..where((t) => t.id.equals(pagoId))).getSingle();
    });
  }

  @override
  Future<AttachmentData> adjuntarComprobante({
    required String pagoId,
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
      await _db.into(_db.pagoAttachment).insert(
            PagoAttachmentCompanion.insert(attachmentId: adjunto.id, pagoId: pagoId),
          );

      await _registrarEventoPago(
        pagoId: pagoId,
        tipoEvento: TipoEventoPago.comprobanteAdjuntado,
        estadoAnterior: null,
        estadoNuevo: null,
        actor: actor,
        datosRelevantes: {'archivoNuevo': originalFileName, 'attachmentId': adjunto.id},
      );

      return adjunto;
    });
  }

  EstatusCuentaPorCobrar _estatusCuentaPorSaldo(int saldoPendiente, int saldoOriginal) {
    if (saldoPendiente <= 0) return EstatusCuentaPorCobrar.pagada;
    if (saldoPendiente < saldoOriginal) return EstatusCuentaPorCobrar.parcial;
    return EstatusCuentaPorCobrar.pendiente;
  }

  Future<void> _registrarEventoPago({
    required String pagoId,
    required TipoEventoPago tipoEvento,
    required String? estadoAnterior,
    required String? estadoNuevo,
    String? observacion,
    String? actor,
    Map<String, Object?>? datosRelevantes,
  }) {
    return _db.into(_db.pagoEvento).insert(
          PagoEventoCompanion.insert(
            pagoId: pagoId,
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

  Future<void> _registrarEventoCuenta({
    required String cuentaPorCobrarId,
    required TipoEventoCuentaPorCobrar tipoEvento,
    required String? estadoAnterior,
    required String? estadoNuevo,
    String? observacion,
    String? actor,
    Map<String, Object?>? datosRelevantes,
  }) {
    return _db.into(_db.cuentaPorCobrarEvento).insert(
          CuentaPorCobrarEventoCompanion.insert(
            cuentaPorCobrarId: cuentaPorCobrarId,
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
