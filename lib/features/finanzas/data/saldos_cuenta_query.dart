import 'package:drift/drift.dart';

import 'package:riseg_one/core/database/app_database.dart';

/// **La única fórmula de saldo de cuenta del proyecto.**
///
/// ```
/// saldo = saldoInicial
///       + Ingresos vigentes            (fecha >= fechaSaldoInicial)
///       − EgresoFuente de Egresos vigentes (fecha >= fechaSaldoInicial)
///       + Transferencias recibidas vigentes
///       − Transferencias enviadas vigentes
/// ```
///
/// Vive aquí, como función libre sobre `AppDatabase`, porque la
/// consumen dos repositorios: `CuentaFinancieraRepositoryImpl`
/// —que la expone al resto del sistema como `calcularSaldos`— y
/// `EgresoRepositoryImpl`, que necesita leer el saldo **dentro de la
/// misma transacción** en la que escribe, para que la lectura que
/// autoriza una salida y la escritura de esa salida no puedan
/// separarse. Una función compartida en lugar de dos implementaciones
/// es lo que impide que existan dos verdades.
///
/// **La salida se cuenta exactamente una vez.** Se lee `EgresoFuente`
/// y **nunca** `Egreso.cuentaFinancieraId`, que desde la v91 es una
/// columna legacy. Sumar ambas sería doble conteo.
///
/// **El corte por `fechaSaldoInicial`** existía desde antes y se
/// conserva: un movimiento anterior a la fecha del saldo inicial de su
/// cuenta ya está representado dentro de ese saldo inicial, así que
/// volver a sumarlo lo contaría dos veces.
///
/// Siempre en lote: 4 consultas para N cuentas, nunca una por cuenta.
Future<Map<String, int>> calcularSaldosCanonico(AppDatabase db, Iterable<String> cuentaIds) async {
  final ids = cuentaIds.toSet();
  if (ids.isEmpty) return {};

  final cuentas = await (db.select(db.cuentaFinanciera)..where((t) => t.id.isIn(ids))).get();
  final corte = {for (final c in cuentas) c.id: c.fechaSaldoInicial};
  final resultado = <String, int>{for (final c in cuentas) c.id: c.saldoInicial};

  bool cuentaElMovimiento(String cuentaId, DateTime fecha) {
    final desde = corte[cuentaId];
    return desde == null || !fecha.isBefore(desde);
  }

  // (1) Ingresos.
  final ingresos = await (db.select(db.ingreso)
        ..where((t) => t.cuentaFinancieraId.isIn(ids) & t.estatus.equals('registrado')))
      .get();
  for (final i in ingresos) {
    final cuentaId = i.cuentaFinancieraId;
    if (cuentaId == null || !cuentaElMovimiento(cuentaId, i.fecha)) continue;
    resultado[cuentaId] = (resultado[cuentaId] ?? 0) + i.monto;
  }

  // (2) Salidas, por sus FUENTES. El `join` trae el estatus y la fecha
  // del Egreso dueño en la misma consulta — nunca una por fuente.
  final filasFuente = await (db.select(db.egresoFuente).join([
    innerJoin(db.egreso, db.egreso.id.equalsExp(db.egresoFuente.egresoId)),
  ])
        ..where(db.egresoFuente.cuentaFinancieraId.isIn(ids) & db.egreso.estatus.equals('registrado')))
      .get();
  for (final fila in filasFuente) {
    final fuente = fila.readTable(db.egresoFuente);
    final egreso = fila.readTable(db.egreso);
    if (!cuentaElMovimiento(fuente.cuentaFinancieraId, egreso.fecha)) continue;
    resultado[fuente.cuentaFinancieraId] = (resultado[fuente.cuentaFinancieraId] ?? 0) - fuente.importe;
  }

  // (3) Transferencias, en una sola consulta para ambos lados.
  final transferencias = await (db.select(db.transferenciaCuenta)
        ..where((t) =>
            (t.cuentaOrigenId.isIn(ids) | t.cuentaDestinoId.isIn(ids)) & t.estatus.equals('registrada')))
      .get();
  for (final t in transferencias) {
    if (ids.contains(t.cuentaOrigenId) && cuentaElMovimiento(t.cuentaOrigenId, t.fecha)) {
      resultado[t.cuentaOrigenId] = (resultado[t.cuentaOrigenId] ?? 0) - t.importe;
    }
    if (ids.contains(t.cuentaDestinoId) && cuentaElMovimiento(t.cuentaDestinoId, t.fecha)) {
      resultado[t.cuentaDestinoId] = (resultado[t.cuentaDestinoId] ?? 0) + t.importe;
    }
  }

  return resultado;
}
