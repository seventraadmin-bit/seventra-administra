import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import '../../domain/repositories/cuenta_financiera_repository.dart';
import '../saldos_cuenta_query.dart';

/// Nunca escribe directo sobre `_db.ingreso`/`_db.egreso` para
/// registrar movimientos — esos siguen naciendo exclusivamente en
/// `IngresoRepository`/`EgresoRepository` (Pago, Compra, PagoNomina,
/// Deuda, manual); este repositorio solo LEE esos movimientos para
/// derivar el saldo/historial de la cuenta, y administra el ciclo de
/// vida propio de `CuentaFinanciera`.
class CuentaFinancieraRepositoryImpl implements CuentaFinancieraRepository {
  CuentaFinancieraRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<CuentaFinancieraData?> obtenerPorId(String id) {
    return (_db.select(_db.cuentaFinanciera)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<CuentaFinancieraData>> listar({bool soloActivas = false}) {
    final query = _db.select(_db.cuentaFinanciera)..orderBy([(t) => OrderingTerm.asc(t.nombre)]);
    if (soloActivas) query.where((t) => t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name));
    return query.get();
  }

  @override
  Future<int> calcularSaldo(String cuentaId) async {
    final saldos = await calcularSaldos([cuentaId]);
    return saldos[cuentaId] ?? 0;
  }

  @override
  Future<Map<String, int>> calcularSaldos(Iterable<String> cuentaIds) {
    // Delegado a `calcularSaldosCanonico`, la única fórmula del
    // proyecto. Este repositorio sigue siendo la puerta pública, pero
    // ya no posee la fórmula: el embudo de Egresos necesita la misma,
    // dentro de su propia transacción, y dos copias serían dos
    // verdades.
    return calcularSaldosCanonico(_db, cuentaIds);
  }

  @override
  /// El historial se deriva de las MISMAS fuentes que el saldo, no de
  /// `Egreso.cuentaFinancieraId` (legacy desde la v91).
  ///
  /// Leerlo de la columna tenía dos fallos reales: un Egreso pagado
  /// entre varias cuentas la deja en `null` y habría desaparecido del
  /// historial de ambas, y una fuente parcial habría mostrado el
  /// importe completo. Ahora cada renglón sale del importe que esa
  /// cuenta puso, así que historial y saldo cuentan lo mismo.
  ///
  /// Las transferencias también aparecen: mueven la cuenta, así que
  /// omitirlas dejaría un historial que no explica su propio saldo.
  /// 3 consultas fijas, nunca una por movimiento.
  Future<List<MovimientoCuentaFinanciera>> listarMovimientos(String cuentaId) async {
    final ingresos = await (_db.select(_db.ingreso)..where((t) => t.cuentaFinancieraId.equals(cuentaId))).get();

    final filas = await (_db.select(_db.egresoFuente).join([
      innerJoin(_db.egreso, _db.egreso.id.equalsExp(_db.egresoFuente.egresoId)),
    ])
          ..where(_db.egresoFuente.cuentaFinancieraId.equals(cuentaId)))
        .get();

    final transferencias = await (_db.select(_db.transferenciaCuenta)
          ..where((t) => t.cuentaOrigenId.equals(cuentaId) | t.cuentaDestinoId.equals(cuentaId)))
        .get();

    final movimientos = <MovimientoCuentaFinanciera>[
      for (final i in ingresos)
        (fecha: i.fecha, concepto: i.concepto, referencia: i.folioIngreso, entrada: i.monto, salida: 0, esIngreso: true, origenId: i.id),
      for (final fila in filas)
        (
          fecha: fila.readTable(_db.egreso).fecha,
          concepto: fila.readTable(_db.egreso).concepto,
          referencia: fila.readTable(_db.egreso).folioEgreso,
          entrada: 0,
          // El importe de ESTA cuenta, no el total del Egreso.
          salida: fila.readTable(_db.egresoFuente).importe,
          esIngreso: false,
          origenId: fila.readTable(_db.egreso).id,
        ),
      for (final t in transferencias)
        (
          fecha: t.fecha,
          concepto: t.concepto ?? t.folioTransferencia,
          referencia: t.folioTransferencia,
          entrada: t.cuentaDestinoId == cuentaId ? t.importe : 0,
          salida: t.cuentaOrigenId == cuentaId ? t.importe : 0,
          esIngreso: t.cuentaDestinoId == cuentaId,
          origenId: t.id,
        ),
    ]..sort((a, b) => a.fecha.compareTo(b.fecha));

    return movimientos;
  }

  @override
  Future<CuentaFinancieraData> crear({
    required String codigo,
    required String nombre,
    required String tipo,
    String? institucionId,
    String? ultimosDigitos,
    required int saldoInicial,
    required DateTime fechaSaldoInicial,
    String? observaciones,
  }) {
    return _db.into(_db.cuentaFinanciera).insertReturning(
          CuentaFinancieraCompanion.insert(
            codigo: codigo,
            nombre: nombre,
            tipo: tipo,
            institucionId: Value(institucionId),
            ultimosDigitos: Value(ultimosDigitos),
            saldoInicial: saldoInicial,
            fechaSaldoInicial: fechaSaldoInicial,
            observaciones: Value(observaciones),
          ),
        );
  }

  @override
  Future<CuentaFinancieraData> corregir({
    required String cuentaId,
    String? nombre,
    String? institucionId,
    bool limpiarInstitucionId = false,
    String? ultimosDigitos,
    bool limpiarUltimosDigitos = false,
    String? observaciones,
  }) async {
    await (_db.update(_db.cuentaFinanciera)..where((t) => t.id.equals(cuentaId))).write(
      CuentaFinancieraCompanion(
        nombre: nombre == null ? const Value.absent() : Value(nombre),
        institucionId:
            limpiarInstitucionId ? const Value(null) : (institucionId == null ? const Value.absent() : Value(institucionId)),
        ultimosDigitos:
            limpiarUltimosDigitos ? const Value(null) : (ultimosDigitos == null ? const Value.absent() : Value(ultimosDigitos)),
        observaciones: observaciones == null ? const Value.absent() : Value(observaciones),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (await obtenerPorId(cuentaId))!;
  }

  @override
  Future<CuentaFinancieraData> activar(String cuentaId) async {
    await (_db.update(_db.cuentaFinanciera)..where((t) => t.id.equals(cuentaId))).write(
      CuentaFinancieraCompanion(cicloVidaRegistro: Value(CicloVidaRegistro.activo.name), updatedAt: Value(DateTime.now())),
    );
    return (await obtenerPorId(cuentaId))!;
  }

  @override
  Future<CuentaFinancieraData> desactivar(String cuentaId) async {
    await (_db.update(_db.cuentaFinanciera)..where((t) => t.id.equals(cuentaId))).write(
      CuentaFinancieraCompanion(cicloVidaRegistro: Value(CicloVidaRegistro.inactivo.name), updatedAt: Value(DateTime.now())),
    );
    return (await obtenerPorId(cuentaId))!;
  }

  @override
  Future<ResumenEliminacionCuentaFinanciera> obtenerResumenEliminacionFisica(String cuentaId) async {
    final cuenta = await obtenerPorId(cuentaId);
    if (cuenta == null) return const ResumenEliminacionCuentaFinanciera(existe: false);

    final tieneIngresos = await (_db.select(_db.ingreso)..where((t) => t.cuentaFinancieraId.equals(cuentaId))).get();
    if (tieneIngresos.isNotEmpty) {
      return ResumenEliminacionCuentaFinanciera(
        existe: true,
        detalleBloqueo: 'Esta cuenta tiene ${tieneIngresos.length} Ingreso(s) vinculado(s) — no puede eliminarse.',
      );
    }
    // Por FUENTES, no por la columna legacy: un Egreso pagado entre
    // varias cuentas la deja en `null`, y preguntar por ella habría
    // dado vía libre a borrar una cuenta con salidas reales.
    final tieneEgresos =
        await (_db.select(_db.egresoFuente)..where((t) => t.cuentaFinancieraId.equals(cuentaId))).get();
    if (tieneEgresos.isNotEmpty) {
      return ResumenEliminacionCuentaFinanciera(
        existe: true,
        detalleBloqueo: 'Esta cuenta tiene ${tieneEgresos.length} Egreso(s) vinculado(s) — no puede eliminarse.',
      );
    }
    // Una transferencia también ata la cuenta, por cualquiera de sus
    // dos lados.
    final tieneTransferencias = await (_db.select(_db.transferenciaCuenta)
          ..where((t) => t.cuentaOrigenId.equals(cuentaId) | t.cuentaDestinoId.equals(cuentaId)))
        .get();
    if (tieneTransferencias.isNotEmpty) {
      return ResumenEliminacionCuentaFinanciera(
        existe: true,
        detalleBloqueo: 'Esta cuenta tiene ${tieneTransferencias.length} transferencia(s) vinculada(s) — no puede eliminarse.',
      );
    }
    return const ResumenEliminacionCuentaFinanciera(existe: true);
  }

  @override
  Future<EliminarCuentaFinancieraFisicamenteResultado> eliminarFisicamente({
    required String cuentaId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final cuenta = await obtenerPorId(cuentaId);
    if (cuenta == null) return EliminarCuentaFinancieraFisicamenteNoExiste();

    final resumen = await obtenerResumenEliminacionFisica(cuentaId);
    if (resumen.bloqueado) {
      return EliminarCuentaFinancieraFisicamenteTieneDependencias(resumen.detalleBloqueo!);
    }

    await _db.transaction(() async {
      await _db.into(_db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'cuenta_financiera',
              entidadIdOriginal: cuentaId,
              fechaHora: DateTime.now(),
              motivo: motivo,
              actorUsuarioId: Value(actorUsuarioId),
              snapshotJson: jsonEncode({'cuentaFinanciera': cuenta.toJson()}),
            ),
          );
      await (_db.delete(_db.cuentaFinanciera)..where((t) => t.id.equals(cuentaId))).go();
    });

    return EliminarCuentaFinancieraFisicamenteExitoso();
  }
}
