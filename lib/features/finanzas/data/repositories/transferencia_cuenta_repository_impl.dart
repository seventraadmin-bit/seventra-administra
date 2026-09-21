import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/transferencia_cuenta_table.dart';

import '../../domain/politica_saldo_cuenta.dart';
import '../saldos_cuenta_query.dart';

/// Escrituras de `TransferenciaCuenta`.
///
/// Una transferencia es **una sola fila**: no hay un movimiento de
/// salida y otro de entrada que puedan quedar desparejados. Su efecto
/// sobre los saldos lo deriva `calcularSaldosCanonico` leyendo esa fila
/// por los dos lados, así que "sale de A y entra a B" es literalmente
/// atómico — no hay forma de escribir la mitad.
class TransferenciaCuentaRepositoryImpl {
  TransferenciaCuentaRepositoryImpl(this._db);

  final AppDatabase _db;

  Future<TransferenciaCuentaData?> obtenerPorId(String id) {
    return (_db.select(_db.transferenciaCuenta)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<List<TransferenciaCuentaData>> listar({String? cuentaId}) {
    final query = _db.select(_db.transferenciaCuenta)..orderBy([(t) => OrderingTerm.desc(t.fecha)]);
    if (cuentaId != null) {
      query.where((t) => t.cuentaOrigenId.equals(cuentaId) | t.cuentaDestinoId.equals(cuentaId));
    }
    return query.get();
  }

  Future<List<TransferenciaCuentaEventoData>> listarEventos(String transferenciaId) {
    return (_db.select(_db.transferenciaCuentaEvento)
          ..where((t) => t.transferenciaCuentaId.equals(transferenciaId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaHora)]))
        .get();
  }

  /// Verifica la política sobre la cuenta de ORIGEN y la fecha sobre
  /// **ambas**: recibir dinero nunca se bloquea por saldo, pero sí por
  /// una fecha anterior al saldo inicial del destino, porque ese abono
  /// tampoco se sumaría.
  ///
  /// [transferenciaExcluida] es lo que permite corregir sin contarse a
  /// sí misma: al pasar su id, la lectura del saldo descuenta el efecto
  /// que la propia transferencia tiene hoy.
  Future<void> _verificar({
    required String cuentaOrigenId,
    required String cuentaDestinoId,
    required int importe,
    required DateTime fecha,
    String? transferenciaExcluida,
  }) async {
    final cuentas = await (_db.select(_db.cuentaFinanciera)
          ..where((t) => t.id.isIn([cuentaOrigenId, cuentaDestinoId])))
        .get();
    final porId = {for (final c in cuentas) c.id: c};
    final saldos = await calcularSaldosCanonico(_db, [cuentaOrigenId, cuentaDestinoId]);

    var disponibleOrigen = saldos[cuentaOrigenId] ?? 0;
    if (transferenciaExcluida != null) {
      final actual = await obtenerPorId(transferenciaExcluida);
      if (actual != null && actual.estatus == EstatusTransferenciaCuenta.registrada.name) {
        if (actual.cuentaOrigenId == cuentaOrigenId) disponibleOrigen += actual.importe;
        if (actual.cuentaDestinoId == cuentaOrigenId) disponibleOrigen -= actual.importe;
      }
    }

    const politica = PoliticaSaldoCuenta();
    final origen = politica.verificar(
      cuenta: porId[cuentaOrigenId],
      disponible: disponibleOrigen,
      requerido: importe,
      fechaMovimiento: fecha,
    );
    if (origen is! SaldoSuficiente) throw SaldoInsuficienteException(origen);

    // El destino sólo recibe: `requerido: 0` deja pasar el saldo y deja
    // viva la comprobación de fecha y de cuenta activa.
    final destino = politica.verificar(
      cuenta: porId[cuentaDestinoId],
      disponible: saldos[cuentaDestinoId] ?? 0,
      requerido: 0,
      fechaMovimiento: fecha,
    );
    if (destino is! SaldoSuficiente) throw SaldoInsuficienteException(destino);
  }

  Future<TransferenciaCuentaData> crear({
    required String folioTransferencia,
    required String cuentaOrigenId,
    required String cuentaDestinoId,
    required int importe,
    required DateTime fecha,
    String? concepto,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      await _verificar(
        cuentaOrigenId: cuentaOrigenId,
        cuentaDestinoId: cuentaDestinoId,
        importe: importe,
        fecha: fecha,
      );

      final transferencia = await _db.into(_db.transferenciaCuenta).insertReturning(
            TransferenciaCuentaCompanion.insert(
              folioTransferencia: folioTransferencia,
              cuentaOrigenId: cuentaOrigenId,
              cuentaDestinoId: cuentaDestinoId,
              importe: importe,
              fecha: fecha,
              concepto: Value(concepto),
              observaciones: Value(observaciones),
            ),
          );

      await _registrarEvento(
        transferenciaId: transferencia.id,
        tipoEvento: TipoEventoTransferenciaCuenta.creada,
        estadoAnterior: null,
        estadoNuevo: transferencia.estatus,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'folioTransferencia': folioTransferencia,
          'cuentaOrigenId': cuentaOrigenId,
          'cuentaDestinoId': cuentaDestinoId,
          'importe': importe,
        },
      );

      return transferencia;
    });
  }

  /// Corrige importe, fecha, concepto u observaciones.
  ///
  /// **Nunca las cuentas**: cambiar origen o destino es otra
  /// transferencia, no una corrección de ésta, y se hace cancelando y
  /// creando una nueva (decisión explícita de Marlon).
  Future<TransferenciaCuentaData> corregir({
    required String transferenciaId,
    int? importe,
    DateTime? fecha,
    String? concepto,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.transferenciaCuenta)..where((t) => t.id.equals(transferenciaId)))
          .getSingle();

      if (anterior.estatus != EstatusTransferenciaCuenta.registrada.name) {
        throw StateError('La transferencia ${anterior.folioTransferencia} está cancelada: no se corrige.');
      }

      await _verificar(
        cuentaOrigenId: anterior.cuentaOrigenId,
        cuentaDestinoId: anterior.cuentaDestinoId,
        importe: importe ?? anterior.importe,
        fecha: fecha ?? anterior.fecha,
        transferenciaExcluida: transferenciaId,
      );

      await (_db.update(_db.transferenciaCuenta)..where((t) => t.id.equals(transferenciaId))).write(
        TransferenciaCuentaCompanion(
          importe: importe == null ? const Value.absent() : Value(importe),
          fecha: fecha == null ? const Value.absent() : Value(fecha),
          concepto: concepto == null ? const Value.absent() : Value(concepto),
          observaciones: observaciones == null ? const Value.absent() : Value(observaciones),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final diff = DiffEvento();
      if (importe != null) diff.anotar('importe', anterior.importe, importe);
      if (fecha != null) diff.anotar('fecha', anterior.fecha, fecha);
      if (concepto != null) diff.anotar('concepto', anterior.concepto, concepto);
      if (observaciones != null) diff.anotar('observaciones', anterior.observaciones, observaciones);

      // Mismo formato de diff que `EgresoEvento`: el antes y el
      // después de los campos que de verdad cambiaron.
      await _registrarEvento(
        transferenciaId: transferenciaId,
        tipoEvento: TipoEventoTransferenciaCuenta.corregida,
        estadoAnterior: diff.estadoAnteriorJson ?? anterior.estatus,
        estadoNuevo: diff.estadoNuevoJson ?? anterior.estatus,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
      );

      return (_db.select(_db.transferenciaCuenta)..where((t) => t.id.equals(transferenciaId))).getSingle();
    });
  }

  /// Cancelar devuelve el dinero a su cuenta de origen sin crear ningún
  /// movimiento compensatorio: `calcularSaldos` sólo suma las
  /// transferencias `registrada`, así que basta con el cambio de
  /// estatus. La fila se conserva como historia.
  Future<TransferenciaCuentaData> cancelar({
    required String transferenciaId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.transferenciaCuenta)..where((t) => t.id.equals(transferenciaId)))
          .getSingle();

      await (_db.update(_db.transferenciaCuenta)..where((t) => t.id.equals(transferenciaId))).write(
        TransferenciaCuentaCompanion(
          estatus: Value(EstatusTransferenciaCuenta.cancelada.name),
          motivoCancelacion: Value(motivo),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEvento(
        transferenciaId: transferenciaId,
        tipoEvento: TipoEventoTransferenciaCuenta.cancelada,
        estadoAnterior: anterior.estatus,
        estadoNuevo: EstatusTransferenciaCuenta.cancelada.name,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
      );

      return (_db.select(_db.transferenciaCuenta)..where((t) => t.id.equals(transferenciaId))).getSingle();
    });
  }

  Future<void> _registrarEvento({
    required String transferenciaId,
    required TipoEventoTransferenciaCuenta tipoEvento,
    String? estadoAnterior,
    String? estadoNuevo,
    String? observacion,
    String? actorUsuarioId,
    Map<String, Object?>? datosRelevantes,
  }) {
    return _db.into(_db.transferenciaCuentaEvento).insert(
          TransferenciaCuentaEventoCompanion.insert(
            transferenciaCuentaId: transferenciaId,
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
