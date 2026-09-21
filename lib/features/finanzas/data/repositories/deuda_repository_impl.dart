import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/egreso_repository.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/calcular_fecha_tarjeta_usecase.dart';

import '../../domain/repositories/deuda_repository.dart';

/// Compone `EgresoRepository` real para cada pago — nunca escribe
/// directo sobre `_db.egreso`, mismo criterio que `CompraRepositoryImpl`/
/// `PagoNominaRepositoryImpl`.
class DeudaRepositoryImpl implements DeudaRepository {
  DeudaRepositoryImpl(this._db, this._egresoRepository);

  final AppDatabase _db;
  final EgresoRepository _egresoRepository;

  @override
  Future<DeudaData?> obtenerPorId(String id) {
    return (_db.select(_db.deuda)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<DeudaData>> listar({String? tipo, String? estatus, String? busqueda}) {
    final query = _db.select(_db.deuda)..orderBy([(t) => OrderingTerm.desc(t.fechaOrigen)]);
    if (tipo != null) query.where((t) => t.tipo.equals(tipo));
    if (estatus != null) query.where((t) => t.estatus.equals(estatus));
    if (busqueda != null && busqueda.trim().isNotEmpty) {
      final patron = '%${busqueda.trim()}%';
      query.where((t) => t.nombre.like(patron) | t.folio.like(patron) | t.acreedor.like(patron));
    }
    return query.get();
  }

  @override
  Future<List<MovimientoDeudaData>> listarMovimientos(String deudaId) {
    final query = _db.select(_db.movimientoDeuda)
      ..where((t) => t.deudaId.equals(deudaId))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.get();
  }

  @override
  Future<int> totalSaldoActivo() async {
    final query = _db.selectOnly(_db.deuda)
      ..addColumns([_db.deuda.saldoActual.sum()])
      ..where(_db.deuda.estatus.equals(EstatusDeuda.activa.name));
    final fila = await query.getSingle();
    return fila.read(_db.deuda.saldoActual.sum()) ?? 0;
  }

  @override
  Future<List<String>> listarEgresoIdsDePagosEnRango({DateTime? rangoInicio, DateTime? rangoFin}) async {
    final query = _db.select(_db.movimientoDeuda)..where((t) => t.tipo.equals(TipoMovimientoDeuda.pago.name) & t.egresoId.isNotNull());
    if (rangoInicio != null) query.where((t) => t.fecha.isBiggerOrEqualValue(rangoInicio));
    if (rangoFin != null) query.where((t) => t.fecha.isSmallerOrEqualValue(rangoFin));
    final movimientos = await query.get();
    return [for (final m in movimientos) m.egresoId!];
  }

  @override
  Future<String?> obtenerDeudaIdPorEgresoDePago(String egresoId) async {
    final movimiento = await (_db.select(_db.movimientoDeuda)
          ..where((t) => t.tipo.equals(TipoMovimientoDeuda.pago.name) & t.egresoId.equals(egresoId)))
        .getSingleOrNull();
    return movimiento?.deudaId;
  }

  @override
  Future<Map<String, int>> totalPagadoPorDeuda({List<String>? deudaIds}) async {
    // Etapa 9: "Pagado" es el NETO — el importe de cada pago corregido
    // por sus ajustes y anulado por su reversión. Antes sumaba solo
    // `tipo == pago`, lo que tras una corrección a la baja habría
    // mostrado el importe original (el que se capturó por error) en vez
    // del real. Una sola consulta para todas las Deudas, nunca N+1.
    final query = _db.select(_db.movimientoDeuda)
      ..where(
        (t) => t.tipo.isIn([
          TipoMovimientoDeuda.pago.name,
          TipoMovimientoDeuda.ajustePositivo.name,
          TipoMovimientoDeuda.ajusteNegativo.name,
          TipoMovimientoDeuda.reversionPago.name,
        ]),
      );
    if (deudaIds != null) query.where((t) => t.deudaId.isIn(deudaIds));
    final movimientos = await query.get();

    final totales = <String, int>{};
    for (final m in movimientos) {
      final aporte = _aportePagado(m);
      if (aporte == 0) continue;
      totales[m.deudaId] = (totales[m.deudaId] ?? 0) + aporte;
    }
    return totales;
  }

  /// Cuánto suma (o resta) un movimiento al total PAGADO de su Deuda.
  ///
  /// Un `pago` aporta su importe. Los movimientos vinculados a un pago
  /// (`movimientoOrigenId != null`) lo corrigen: un `ajustePositivo`
  /// devuelve saldo a la deuda, o sea que se pagó MENOS (resta), un
  /// `ajusteNegativo` es lo contrario (suma), y una `reversionPago`
  /// anula el pago completo (resta). Los ajustes de un CARGO
  /// (`movimientoOrigenId == null`) no son pagos y no cuentan aquí —
  /// ese es justo el papel discriminador de la FK.
  int _aportePagado(MovimientoDeudaData m) {
    if (m.tipo == TipoMovimientoDeuda.pago.name) return m.importe;
    if (m.movimientoOrigenId == null) return 0;
    return switch (m.tipo) {
      final t when t == TipoMovimientoDeuda.ajustePositivo.name => -m.importe,
      final t when t == TipoMovimientoDeuda.ajusteNegativo.name => m.importe,
      final t when t == TipoMovimientoDeuda.reversionPago.name => -m.importe,
      _ => 0,
    };
  }

  @override
  Future<int> totalCargadoEnRango({DateTime? rangoInicio, DateTime? rangoFin}) async {
    // BUG REAL corregido en la Etapa "Origen financiero de Egresos
    // manuales": esta suma contaba SOLO `cargoCompra`, ignorando los
    // `ajustePositivo`/`ajusteNegativo` que corrigen o revierten ese
    // mismo cargo. Consecuencia: cancelar una Compra pagada con TDC
    // (o corregirle el monto hacia abajo en la misma tarjeta) dejaba el
    // gasto original contado íntegro en `ResumenFinancieroState
    // .cargosTarjetaPeriodo` — y por lo tanto en `egresosOperativos` y
    // en el Resultado operativo—, aunque el saldo de la tarjeta sí se
    // hubiera revertido correctamente. Afectaba por igual a Compras y
    // Tiempos Extra desde que existen sus correcciones; se encontró al
    // verificar "efecto operativo neto del gasto cancelado = 0" del
    // punto 14 del pedido.
    //
    // Los tres tipos se netean con el MISMO criterio que
    // `_calcularNetoAportado` (ajusteNegativo resta, el resto suma), y
    // nunca se filtra por origen: reconoce el gasto sin importar si lo
    // generó una Compra, un Tiempo Extra o un Egreso manual.
    //
    // Etapa 9: además se EXCLUYEN los ajustes vinculados a un pago
    // (`movimientoOrigenId != null`). Corregir un pago de tarjeta no es
    // un gasto —es mover dinero para saldar una deuda ya reconocida—,
    // así que contarlo aquí inflaría el Resultado operativo con una
    // realidad que nunca fue gasto. La FK es el discriminador exacto;
    // los ajustes de un CARGO siguen contando como siempre.
    //
    // Rediseno de Reportes: el predicado dejo de vivir aqui. Esta cifra
    // es literalmente el fold de [listarCargosEnRango] — la grafica
    // temporal de Reportes usa esa misma lista, asi que la suma de las
    // barras y este KPI no pueden diferir ni aunque alguien cambie el
    // criterio manana.
    final cargos = await listarCargosEnRango(rangoInicio: rangoInicio, rangoFin: rangoFin);
    return cargos.fold<int>(0, (acc, c) => acc + c.importeNeto);
  }

  @override
  Future<List<CargoOperativoTarjeta>> listarCargosEnRango({DateTime? rangoInicio, DateTime? rangoFin}) async {
    final query = _db.select(_db.movimientoDeuda)
      ..where(
        (t) =>
            t.tipo.isIn([
              TipoMovimientoDeuda.cargoCompra.name,
              TipoMovimientoDeuda.ajustePositivo.name,
              TipoMovimientoDeuda.ajusteNegativo.name,
            ]) &
            t.movimientoOrigenId.isNull(),
      );
    if (rangoInicio != null) query.where((t) => t.fecha.isBiggerOrEqualValue(rangoInicio));
    if (rangoFin != null) query.where((t) => t.fecha.isSmallerOrEqualValue(rangoFin));
    final movimientos = await query.get();
    return [
      for (final m in movimientos)
        CargoOperativoTarjeta(
          deudaId: m.deudaId,
          fecha: m.fecha,
          importeNeto: m.tipo == TipoMovimientoDeuda.ajusteNegativo.name ? -m.importe : m.importe,
          compraId: m.compraId,
          tiempoExtraId: m.tiempoExtraId,
          costoAdicionalId: m.costoAdicionalId,
          vehiculoMantenimientoId: m.vehiculoMantenimientoId,
          egresoGastoId: m.egresoGastoId,
        ),
    ];
  }

  @override
  Future<int> totalPagadoEnRango({DateTime? rangoInicio, DateTime? rangoFin, String? tipo}) async {
    // Etapa 9: mismo neteo que `totalPagadoPorDeuda` — un pago
    // corregido a la baja o cancelado dejaría de otra forma inflada la
    // cifra "Pagos de tarjetas del periodo" del Resumen.
    final query = _db.select(_db.movimientoDeuda).join([
      innerJoin(_db.deuda, _db.deuda.id.equalsExp(_db.movimientoDeuda.deudaId)),
    ])
      ..where(
        _db.movimientoDeuda.tipo.isIn([
          TipoMovimientoDeuda.pago.name,
          TipoMovimientoDeuda.ajustePositivo.name,
          TipoMovimientoDeuda.ajusteNegativo.name,
          TipoMovimientoDeuda.reversionPago.name,
        ]),
      );
    if (tipo != null) query.where(_db.deuda.tipo.equals(tipo));
    if (rangoInicio != null) query.where(_db.movimientoDeuda.fecha.isBiggerOrEqualValue(rangoInicio));
    if (rangoFin != null) query.where(_db.movimientoDeuda.fecha.isSmallerOrEqualValue(rangoFin));
    final filas = await query.get();
    return filas.fold<int>(0, (acc, fila) => acc + _aportePagado(fila.readTable(_db.movimientoDeuda)));
  }

  @override
  Future<List<DeudaData>> listarTarjetasActivas() {
    return (_db.select(_db.deuda)
          ..where((t) => t.tipo.equals(TipoDeuda.tarjetaCredito.name) & t.estatus.equals(EstatusDeuda.activa.name))
          ..orderBy([(t) => OrderingTerm.asc(t.nombre)]))
        .get();
  }

  @override
  Future<Map<String, DeudaData>> listarPorIds(Iterable<String> ids) async {
    final idsSet = ids.toSet();
    if (idsSet.isEmpty) return {};
    final deudas = await (_db.select(_db.deuda)..where((t) => t.id.isIn(idsSet))).get();
    return {for (final d in deudas) d.id: d};
  }

  @override
  Future<DeudaData> crear({
    required String folio,
    required String nombre,
    required String tipo,
    String? acreedor,
    DateTime? fechaOrigen,
    int? importeOriginal,
    required int saldoInicial,
    DateTime? fechaSaldoInicial,
    DateTime? fechaVencimiento,
    int? pagoProgramado,
    String? periodicidad,
    double? tasaInteres,
    String? referencia,
    String? observaciones,
    String? tarjetaUltimosDigitos,
    int? tarjetaLimiteCredito,
    int? tarjetaDiaCorte,
    int? tarjetaDiaPago,
    int? tarjetaPagoMinimo,
    String? tarjetaReglaFechaPago,
    int? tarjetaDiasDespuesCorte,
    String? tarjetaTipoTasa,
    String? tarjetaTasaReferencia,
    double? tarjetaTasaDiferencial,
    bool? tarjetaTasaMasIva,
    String? tarjetaTasaDescripcion,
    double? tarjetaCat,
    bool? tarjetaCatIncluyeIva,
    DateTime? tarjetaVencimientoCubiertoHasta,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final deuda = await _db.into(_db.deuda).insertReturning(
            DeudaCompanion.insert(
              folio: folio,
              nombre: nombre,
              tipo: tipo,
              acreedor: Value(acreedor),
              fechaOrigen: Value(fechaOrigen),
              importeOriginal: Value(importeOriginal),
              saldoActual: saldoInicial,
              fechaSaldoInicial: Value(fechaSaldoInicial),
              fechaVencimiento: Value(fechaVencimiento),
              pagoProgramado: Value(pagoProgramado),
              periodicidad: Value(periodicidad),
              tasaInteres: Value(tasaInteres),
              referencia: Value(referencia),
              observaciones: Value(observaciones),
              tarjetaUltimosDigitos: Value(tarjetaUltimosDigitos),
              tarjetaLimiteCredito: Value(tarjetaLimiteCredito),
              tarjetaDiaCorte: Value(tarjetaDiaCorte),
              tarjetaDiaPago: Value(tarjetaDiaPago),
              tarjetaPagoMinimo: Value(tarjetaPagoMinimo),
              tarjetaReglaFechaPago: Value(tarjetaReglaFechaPago),
              tarjetaDiasDespuesCorte: Value(tarjetaDiasDespuesCorte),
              tarjetaTipoTasa: Value(tarjetaTipoTasa),
              tarjetaTasaReferencia: Value(tarjetaTasaReferencia),
              tarjetaTasaDiferencial: Value(tarjetaTasaDiferencial),
              tarjetaTasaMasIva: Value(tarjetaTasaMasIva),
              tarjetaTasaDescripcion: Value(tarjetaTasaDescripcion),
              tarjetaCat: Value(tarjetaCat),
              tarjetaCatIncluyeIva: Value(tarjetaCatIncluyeIva),
              tarjetaVencimientoCubiertoHasta: Value(tarjetaVencimientoCubiertoHasta),
            ),
          );

      // Movimiento de apertura — nunca genera Egreso, cubra o no el
      // saldo inicial el importe original completo (deuda nueva vs.
      // histórica migrada, ver el doc comment de `Deuda`). Se omite si
      // `saldoInicial == 0` (una tarjeta/deuda nueva sin cargos previos,
      // caso real y explícitamente válido para `RegistrarDeudaUseCase`)
      // — auditoría integral 19A-19D, bug real encontrado: `importe` de
      // `MovimientoDeuda` tiene `CHECK (importe > 0)`, así que insertar
      // un movimiento de $0 siempre lanzaba `SqliteException` y nunca
      // dejaba crear la Deuda. La fecha del movimiento prioriza
      // `fechaSaldoInicial` sobre `fechaOrigen` — una tarjeta que ya
      // existía antes de RISEG ONE tiene ambas fechas distintas por
      // diseño (Etapa "tarjeta revolvente").
      if (saldoInicial > 0) {
        await _db.into(_db.movimientoDeuda).insert(
              MovimientoDeudaCompanion.insert(
                deudaId: deuda.id,
                fecha: fechaSaldoInicial ?? fechaOrigen ?? DateTime.now(),
                tipo: TipoMovimientoDeuda.altaInicial.name,
                importe: saldoInicial,
                saldoAnterior: 0,
                saldoPosterior: saldoInicial,
                actorUsuarioId: Value(actorUsuarioId),
              ),
            );
      }

      return deuda;
    });
  }

  @override
  Future<DeudaData> corregir({
    required String deudaId,
    String? nombre,
    String? acreedor,
    DateTime? fechaOrigen,
    bool limpiarFechaOrigen = false,
    DateTime? fechaVencimiento,
    bool limpiarFechaVencimiento = false,
    int? pagoProgramado,
    bool limpiarPagoProgramado = false,
    String? periodicidad,
    bool limpiarPeriodicidad = false,
    double? tasaInteres,
    bool limpiarTasaInteres = false,
    String? referencia,
    String? observaciones,
    String? tarjetaUltimosDigitos,
    int? tarjetaLimiteCredito,
    int? tarjetaDiaCorte,
    int? tarjetaDiaPago,
    int? tarjetaPagoMinimo,
    String? tarjetaReglaFechaPago,
    int? tarjetaDiasDespuesCorte,
    String? tarjetaTipoTasa,
    bool limpiarTarjetaTipoTasa = false,
    String? tarjetaTasaReferencia,
    double? tarjetaTasaDiferencial,
    bool? tarjetaTasaMasIva,
    String? tarjetaTasaDescripcion,
    bool limpiarTasaVariable = false,
    double? tarjetaCat,
    bool? tarjetaCatIncluyeIva,
    bool limpiarCat = false,
    DateTime? tarjetaVencimientoCubiertoHasta,
    bool limpiarTarjetaVencimientoCubierto = false,
  }) async {
    await (_db.update(_db.deuda)..where((t) => t.id.equals(deudaId))).write(
      DeudaCompanion(
        nombre: nombre == null ? const Value.absent() : Value(nombre),
        acreedor: acreedor == null ? const Value.absent() : Value(acreedor),
        fechaOrigen:
            limpiarFechaOrigen ? const Value(null) : (fechaOrigen == null ? const Value.absent() : Value(fechaOrigen)),
        fechaVencimiento: limpiarFechaVencimiento
            ? const Value(null)
            : (fechaVencimiento == null ? const Value.absent() : Value(fechaVencimiento)),
        pagoProgramado: limpiarPagoProgramado
            ? const Value(null)
            : (pagoProgramado == null ? const Value.absent() : Value(pagoProgramado)),
        periodicidad: limpiarPeriodicidad
            ? const Value(null)
            : (periodicidad == null ? const Value.absent() : Value(periodicidad)),
        tasaInteres:
            limpiarTasaInteres ? const Value(null) : (tasaInteres == null ? const Value.absent() : Value(tasaInteres)),
        referencia: referencia == null ? const Value.absent() : Value(referencia),
        observaciones: observaciones == null ? const Value.absent() : Value(observaciones),
        tarjetaUltimosDigitos: tarjetaUltimosDigitos == null ? const Value.absent() : Value(tarjetaUltimosDigitos),
        tarjetaLimiteCredito: tarjetaLimiteCredito == null ? const Value.absent() : Value(tarjetaLimiteCredito),
        tarjetaDiaCorte: tarjetaDiaCorte == null ? const Value.absent() : Value(tarjetaDiaCorte),
        tarjetaDiaPago: tarjetaDiaPago == null ? const Value.absent() : Value(tarjetaDiaPago),
        tarjetaPagoMinimo: tarjetaPagoMinimo == null ? const Value.absent() : Value(tarjetaPagoMinimo),
        tarjetaReglaFechaPago: tarjetaReglaFechaPago == null ? const Value.absent() : Value(tarjetaReglaFechaPago),
        tarjetaDiasDespuesCorte: tarjetaDiasDespuesCorte == null ? const Value.absent() : Value(tarjetaDiasDespuesCorte),
        tarjetaTipoTasa: limpiarTarjetaTipoTasa
            ? const Value(null)
            : (tarjetaTipoTasa == null ? const Value.absent() : Value(tarjetaTipoTasa)),
        tarjetaTasaReferencia: limpiarTasaVariable
            ? const Value(null)
            : (tarjetaTasaReferencia == null ? const Value.absent() : Value(tarjetaTasaReferencia)),
        tarjetaTasaDiferencial: limpiarTasaVariable
            ? const Value(null)
            : (tarjetaTasaDiferencial == null ? const Value.absent() : Value(tarjetaTasaDiferencial)),
        tarjetaTasaMasIva: limpiarTasaVariable
            ? const Value(null)
            : (tarjetaTasaMasIva == null ? const Value.absent() : Value(tarjetaTasaMasIva)),
        tarjetaTasaDescripcion: limpiarTasaVariable
            ? const Value(null)
            : (tarjetaTasaDescripcion == null ? const Value.absent() : Value(tarjetaTasaDescripcion)),
        tarjetaCat: limpiarCat ? const Value(null) : (tarjetaCat == null ? const Value.absent() : Value(tarjetaCat)),
        tarjetaCatIncluyeIva: limpiarCat
            ? const Value(null)
            : (tarjetaCatIncluyeIva == null ? const Value.absent() : Value(tarjetaCatIncluyeIva)),
        tarjetaVencimientoCubiertoHasta: limpiarTarjetaVencimientoCubierto
            ? const Value(null)
            : (tarjetaVencimientoCubiertoHasta == null ? const Value.absent() : Value(tarjetaVencimientoCubiertoHasta)),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (await obtenerPorId(deudaId))!;
  }

  @override
  Future<DeudaData> registrarPago({
    required String deudaId,
    required String folioEgreso,
    required DateTime fecha,
    required int importe,
    required String formaPago,
    String? cuentaCaja,
    String? cuentaFinancieraId,
    String? referencia,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final deuda = await obtenerPorId(deudaId);
      if (deuda == null) throw StateError('Deuda $deudaId no existe.');

      final egreso = await _egresoRepository.crear(
        folioEgreso: folioEgreso,
        monto: importe,
        fecha: fecha,
        cuentaCaja: cuentaCaja,
        cuentaFinancieraId: cuentaFinancieraId,
        formaPago: formaPago,
        beneficiario: deuda.acreedor,
        concepto: 'Pago de deuda ${deuda.folio} · ${deuda.nombre}',
        observaciones: referencia == null ? observaciones : 'Referencia: $referencia'
            '${observaciones == null || observaciones.trim().isEmpty ? '' : ' · $observaciones'}',
        actorUsuarioId: actorUsuarioId,
      );

      final saldoAnterior = deuda.saldoActual;
      final saldoPosterior = saldoAnterior - importe;

      final movimiento = await _db.into(_db.movimientoDeuda).insertReturning(
            MovimientoDeudaCompanion.insert(
              deudaId: deudaId,
              fecha: fecha,
              tipo: TipoMovimientoDeuda.pago.name,
              importe: importe,
              saldoAnterior: saldoAnterior,
              saldoPosterior: saldoPosterior,
              egresoId: Value(egreso.id),
              observaciones: Value(observaciones),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );

      // Etapa 19B: una tarjeta de crédito es revolvente — llegar a
      // saldo 0 no la cierra, sigue activa y reutilizable (a diferencia
      // de un préstamo/financiamiento, que sí se da por `liquidada` al
      // llegar a 0, ver el reporte de la Etapa 19B).
      final debeLiquidarse = saldoPosterior == 0 && deuda.tipo != TipoDeuda.tarjetaCredito.name;

      // Etapa "ciclo de TDC": un pago real registrado en RISEG ONE
      // siempre avanza el ciclo cubierto — nunca hacia atrás
      // (`proximaFechaLimitePago` siempre devuelve una fecha
      // ESTRICTAMENTE posterior al ancla vigente). `null` (regla/día
      // incompletos) deja el campo sin tocar — nunca se inventa un
      // ciclo cubierto con datos insuficientes.
      final nuevoVencimientoCubierto = deuda.tipo == TipoDeuda.tarjetaCredito.name
          ? proximaFechaLimitePago(
              regla: deuda.tarjetaReglaFechaPago,
              diaFijo: deuda.tarjetaDiaPago,
              diaCorte: deuda.tarjetaDiaCorte,
              diasDespuesCorte: deuda.tarjetaDiasDespuesCorte,
              hoy: fecha,
              vencimientoCubiertoHasta: deuda.tarjetaVencimientoCubiertoHasta,
            )
          : null;

      // Etapa 9: se guarda en el propio pago el ancla que había ANTES
      // de avanzarla, para poder deshacer el avance con exactitud si
      // este pago se cancela. Solo cuando el pago realmente movió el
      // ciclo — si `nuevoVencimientoCubierto` es `null` no hubo avance
      // que deshacer. Puede quedar `null` aun habiendo avance: eso
      // significa "la tarjeta no tenía ciclo conciliado antes de este
      // pago", que es exactamente el valor al que hay que volver.
      if (nuevoVencimientoCubierto != null) {
        await (_db.update(_db.movimientoDeuda)..where((t) => t.id.equals(movimiento.id))).write(
          MovimientoDeudaCompanion(
            tarjetaVencimientoCubiertoAnterior: Value(deuda.tarjetaVencimientoCubiertoHasta),
          ),
        );
      }

      await (_db.update(_db.deuda)..where((t) => t.id.equals(deudaId))).write(
        DeudaCompanion(
          saldoActual: Value(saldoPosterior),
          estatus: Value(debeLiquidarse ? EstatusDeuda.liquidada.name : deuda.estatus),
          tarjetaVencimientoCubiertoHasta:
              nuevoVencimientoCubierto == null ? const Value.absent() : Value(nuevoVencimientoCubierto),
          updatedAt: Value(DateTime.now()),
        ),
      );

      return (await obtenerPorId(deudaId))!;
    });
  }

  @override
  Future<MovimientoDeudaData?> obtenerMovimiento(int movimientoId) {
    return (_db.select(_db.movimientoDeuda)..where((t) => t.id.equals(movimientoId))).getSingleOrNull();
  }

  @override
  Future<List<MovimientoDeudaData>> listarMovimientosDePago(int pagoId) {
    return (_db.select(_db.movimientoDeuda)
          ..where((t) => t.movimientoOrigenId.equals(pagoId))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  @override
  Future<EstadoPagoDeuda> obtenerEstadoPago(int pagoId) async {
    final pago = await obtenerMovimiento(pagoId);
    if (pago == null || pago.tipo != TipoMovimientoDeuda.pago.name) {
      return const EstadoPagoDeuda(existe: false, cancelado: false, importeNeto: 0, correcciones: 0);
    }
    final vinculados = await listarMovimientosDePago(pagoId);
    final cancelado = vinculados.any((m) => m.tipo == TipoMovimientoDeuda.reversionPago.name);
    final neto = pago.importe + vinculados.fold<int>(0, (acc, m) => acc + _aportePagado(m));
    return EstadoPagoDeuda(
      existe: true,
      cancelado: cancelado,
      importeNeto: neto,
      correcciones: vinculados.where((m) => m.tipo != TipoMovimientoDeuda.reversionPago.name).length,
    );
  }

  /// Recalcula `estatus` tras mover el saldo de una deuda fija.
  ///
  /// Una tarjeta de crédito nunca entra aquí: es revolvente, llegar a 0
  /// no la liquida (Etapa 19B). Para préstamo/financiamiento el estatus
  /// sigue SIEMPRE al saldo, en los dos sentidos — llegar a 0 liquida,
  /// y volver a tener saldo por una corrección o una cancelación
  /// devuelve a `activa`. Nunca queda una Deuda `liquidada` con saldo
  /// mayor que cero (punto 8 del pedido).
  String _estatusSegunSaldo(DeudaData deuda, int saldoPosterior) {
    if (deuda.estatus == EstatusDeuda.cancelada.name) return deuda.estatus;
    if (deuda.tipo == TipoDeuda.tarjetaCredito.name) return deuda.estatus;
    return saldoPosterior == 0 ? EstatusDeuda.liquidada.name : EstatusDeuda.activa.name;
  }

  /// Escribe un movimiento vinculado a [pago] que mueve el saldo en
  /// [deltaSaldo] (positivo = la deuda vuelve a subir porque se pagó
  /// menos) y actualiza `saldoActual`/`estatus`. Cuerpo compartido por
  /// la corrección de monto y la cancelación — nunca reescribe la fila
  /// del pago original.
  Future<void> _escribirMovimientoDePago({
    required DeudaData deuda,
    required MovimientoDeudaData pago,
    required int deltaSaldo,
    required String tipo,
    required String motivo,
    String? actorUsuarioId,
    DateTime? tarjetaVencimientoCubierto,
    bool limpiarTarjetaVencimientoCubierto = false,
  }) async {
    final saldoAnterior = deuda.saldoActual;
    final saldoPosterior = saldoAnterior + deltaSaldo;

    if (deltaSaldo != 0) {
      await _db.into(_db.movimientoDeuda).insert(
            MovimientoDeudaCompanion.insert(
              deudaId: deuda.id,
              fecha: DateTime.now(),
              tipo: tipo,
              importe: deltaSaldo.abs(),
              saldoAnterior: saldoAnterior,
              saldoPosterior: saldoPosterior,
              movimientoOrigenId: Value(pago.id),
              observaciones: Value(motivo),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );
    }

    await (_db.update(_db.deuda)..where((t) => t.id.equals(deuda.id))).write(
      DeudaCompanion(
        saldoActual: Value(saldoPosterior),
        estatus: Value(_estatusSegunSaldo(deuda, saldoPosterior)),
        tarjetaVencimientoCubiertoHasta: limpiarTarjetaVencimientoCubierto
            ? const Value(null)
            : (tarjetaVencimientoCubierto == null ? const Value.absent() : Value(tarjetaVencimientoCubierto)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<DeudaData> corregirPago({
    required int pagoId,
    int? nuevoImporte,
    String? nuevaCuentaFinancieraId,
    bool limpiarCuentaFinanciera = false,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final pago = (await obtenerMovimiento(pagoId))!;
      final deuda = (await obtenerPorId(pago.deudaId))!;
      final estado = await obtenerEstadoPago(pagoId);

      final importeFinal = nuevoImporte ?? estado.importeNeto;

      // 1. Ledger append-only: la diferencia se registra como un ajuste
      //    vinculado al pago, NUNCA reescribiendo su fila. El historial
      //    conserva íntegro lo que se capturó originalmente.
      //    `deltaSaldo > 0` = se pagó menos de lo registrado, así que la
      //    deuda vuelve a subir (`ajustePositivo`).
      final deltaSaldo = estado.importeNeto - importeFinal;
      if (deltaSaldo != 0) {
        await _escribirMovimientoDePago(
          deuda: deuda,
          pago: pago,
          deltaSaldo: deltaSaldo,
          tipo: deltaSaldo > 0 ? TipoMovimientoDeuda.ajustePositivo.name : TipoMovimientoDeuda.ajusteNegativo.name,
          motivo: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      }

      // 2. El Egreso es la MISMA realidad que el pago: se sincroniza
      //    siempre, conservando id y folio. Nunca se cancela y recrea —
      //    y nunca pasa por `CorregirEgresoUseCase`, que bloquea desde
      //    Finanzas justamente este Egreso (composición interna, mismo
      //    criterio que Compra/TiempoExtra con su propio Egreso).
      final egresoId = pago.egresoId;
      if (egresoId != null) {
        final cambiaCuenta = limpiarCuentaFinanciera || nuevaCuentaFinancieraId != null;
        if (cambiaCuenta) {
          await _egresoRepository.corregir(
            egresoId: egresoId,
            cuentaFinancieraId: nuevaCuentaFinancieraId,
            limpiarCuentaFinancieraId: limpiarCuentaFinanciera,
            motivo: motivo,
            actorUsuarioId: actorUsuarioId,
          );
        }
        if (importeFinal != pago.importe || deltaSaldo != 0) {
          await _egresoRepository.corregirMonto(
            egresoId: egresoId,
            nuevoMonto: importeFinal,
            motivo: motivo,
            actorUsuarioId: actorUsuarioId,
          );
        }
      }

      return (await obtenerPorId(deuda.id))!;
    });
  }

  @override
  Future<CancelacionPagoDeuda> cancelarPago({
    required int pagoId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final pago = (await obtenerMovimiento(pagoId))!;
      final deuda = (await obtenerPorId(pago.deudaId))!;
      final estado = await obtenerEstadoPago(pagoId);

      final retroceso = await _resolverRetrocesoCicloTarjeta(deuda: deuda, pago: pago);

      // Revierte el neto vivo: el pago vuelve a deber lo que había
      // saldado, ni más ni menos. `reversionPago` es su propio tipo,
      // así que "¿está cancelado?" se deriva de su existencia — la fila
      // del pago nunca se toca ni se borra.
      await _escribirMovimientoDePago(
        deuda: deuda,
        pago: pago,
        deltaSaldo: estado.importeNeto,
        tipo: TipoMovimientoDeuda.reversionPago.name,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
        tarjetaVencimientoCubierto: retroceso.nuevoAncla,
        limpiarTarjetaVencimientoCubierto: retroceso.retrocede && retroceso.nuevoAncla == null,
      );

      if (pago.egresoId != null) {
        await _egresoRepository.cancelar(
          egresoId: pago.egresoId!,
          motivo: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      }

      return CancelacionPagoDeuda(
        deuda: (await obtenerPorId(deuda.id))!,
        cicloTarjetaRetrocedido: retroceso.retrocede,
        cicloTarjetaRequiereConciliacion: retroceso.requiereConciliacion,
      );
    });
  }

  /// Decide si la cancelación de [pago] puede deshacer el avance del
  /// ciclo de la tarjeta, según la política aprobada por Marlon:
  /// **retroceder un ciclo solo cuando es inequívoco**.
  ///
  /// Es inequívoco cuando se cumplen las dos condiciones:
  ///  1. Este pago es el ÚLTIMO pago vivo de la tarjeta — si hay pagos
  ///     posteriores, ellos también avanzaron el ciclo y podrían estar
  ///     justificando el ancla actual (nunca se retrocede ignorándolos).
  ///  2. El ancla que la Deuda tiene HOY es exactamente la que ESTE
  ///     pago produjo, recalculada desde el valor que guardó en
  ///     `tarjetaVencimientoCubiertoAnterior`. Si no coincide, alguien
  ///     la conció a mano después (`CorregirDeudaUseCase` permite
  ///     editarla y limpiarla) y pisarla sería destruir esa decisión.
  ///
  /// Cuando no es inequívoco, no se toca nada y se devuelve
  /// `requiereConciliacion: true` para que la UI lo diga en voz alta —
  /// nunca se inventa un retroceso ni se deja el dato en silencio.
  /// Un pago anterior a la Etapa 9 (sin ancla guardada) cae siempre en
  /// este caso, igual que uno sobre deuda fija (donde no hay ciclo).
  Future<({bool retrocede, bool requiereConciliacion, DateTime? nuevoAncla})> _resolverRetrocesoCicloTarjeta({
    required DeudaData deuda,
    required MovimientoDeudaData pago,
  }) async {
    if (deuda.tipo != TipoDeuda.tarjetaCredito.name) {
      return (retrocede: false, requiereConciliacion: false, nuevoAncla: null);
    }
    if (deuda.tarjetaVencimientoCubiertoHasta == null) {
      // No hay ciclo cubierto que deshacer.
      return (retrocede: false, requiereConciliacion: false, nuevoAncla: null);
    }

    final pagosPosteriores = await (_db.select(_db.movimientoDeuda)
          ..where((t) => t.deudaId.equals(deuda.id) & t.tipo.equals(TipoMovimientoDeuda.pago.name) & t.id.isBiggerThanValue(pago.id)))
        .get();
    final vivosPosteriores = <MovimientoDeudaData>[];
    for (final posterior in pagosPosteriores) {
      final estado = await obtenerEstadoPago(posterior.id);
      if (!estado.cancelado) vivosPosteriores.add(posterior);
    }
    if (vivosPosteriores.isNotEmpty) {
      return (retrocede: false, requiereConciliacion: true, nuevoAncla: null);
    }

    final anclaProducida = proximaFechaLimitePago(
      regla: deuda.tarjetaReglaFechaPago,
      diaFijo: deuda.tarjetaDiaPago,
      diaCorte: deuda.tarjetaDiaCorte,
      diasDespuesCorte: deuda.tarjetaDiasDespuesCorte,
      hoy: pago.fecha,
      vencimientoCubiertoHasta: pago.tarjetaVencimientoCubiertoAnterior,
    );
    if (anclaProducida == null || anclaProducida != deuda.tarjetaVencimientoCubiertoHasta) {
      return (retrocede: false, requiereConciliacion: true, nuevoAncla: null);
    }

    return (retrocede: true, requiereConciliacion: false, nuevoAncla: pago.tarjetaVencimientoCubiertoAnterior);
  }

  /// Cuerpo compartido de `registrarCargoCompra`/`registrarCargoTiempoExtra`/
  /// `registrarCargoCostoAdicional`/`registrarCargoEgreso` — exactamente
  /// uno de `compraId`/`tiempoExtraId`/`costoAdicionalId`/`egresoGastoId`
  /// se puebla, nunca más de uno (Etapa "origen financiero unificado";
  /// `egresoGastoId` desde la Etapa "Origen financiero de Egresos
  /// manuales"). Aumenta `saldoActual`, inserta
  /// `MovimientoDeuda.cargoCompra` (el nombre persistido no cambia sin
  /// importar el origen — ver el doc comment del enum), **nunca** genera
  /// Egreso: el de `egresoGastoId` ya existía antes de llamar aquí (es
  /// el documento del gasto), nunca se crea uno nuevo.
  Future<DeudaData> _registrarCargo({
    required String deudaId,
    required int monto,
    required DateTime fecha,
    String? compraId,
    String? tiempoExtraId,
    int? costoAdicionalId,
    String? egresoGastoId,
    String? vehiculoMantenimientoId,
    String? recargaLineaTelefonicaId,
    String? servicioEventualCoberturaId,
    String? servicioEventualCostoId,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final deuda = await obtenerPorId(deudaId);
      if (deuda == null) throw StateError('Deuda $deudaId no existe.');

      final saldoAnterior = deuda.saldoActual;
      final saldoPosterior = saldoAnterior + monto;

      await _db.into(_db.movimientoDeuda).insert(
            MovimientoDeudaCompanion.insert(
              deudaId: deudaId,
              fecha: fecha,
              tipo: TipoMovimientoDeuda.cargoCompra.name,
              importe: monto,
              saldoAnterior: saldoAnterior,
              saldoPosterior: saldoPosterior,
              compraId: Value(compraId),
              tiempoExtraId: Value(tiempoExtraId),
              costoAdicionalId: Value(costoAdicionalId),
              egresoGastoId: Value(egresoGastoId),
              vehiculoMantenimientoId: Value(vehiculoMantenimientoId),
              recargaLineaTelefonicaId: Value(recargaLineaTelefonicaId),
              servicioEventualCoberturaId: Value(servicioEventualCoberturaId),
              servicioEventualCostoId: Value(servicioEventualCostoId),
              observaciones: Value(observaciones),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );

      await (_db.update(_db.deuda)..where((t) => t.id.equals(deudaId))).write(
        DeudaCompanion(saldoActual: Value(saldoPosterior), updatedAt: Value(DateTime.now())),
      );

      return (await obtenerPorId(deudaId))!;
    });
  }

  @override
  Future<DeudaData> registrarCargoCompra({
    required String deudaId,
    required String compraId,
    required int monto,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _registrarCargo(
      deudaId: deudaId,
      monto: monto,
      fecha: fecha,
      compraId: compraId,
      observaciones: observaciones,
      actorUsuarioId: actorUsuarioId,
    );
  }

  @override
  Future<DeudaData> registrarCargoTiempoExtra({
    required String deudaId,
    required String tiempoExtraId,
    required int monto,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _registrarCargo(
      deudaId: deudaId,
      monto: monto,
      fecha: fecha,
      tiempoExtraId: tiempoExtraId,
      observaciones: observaciones,
      actorUsuarioId: actorUsuarioId,
    );
  }

  @override
  Future<int> netoAportadoPorMantenimientoVehiculo({
    required String deudaId,
    required String vehiculoMantenimientoId,
  }) {
    return _calcularNetoAportado(deudaId: deudaId, vehiculoMantenimientoId: vehiculoMantenimientoId);
  }

  // --- Vehículos (schemaVersion 80) — mismo trío exacto que Compra y
  // Tiempo Extra, delegando en los helpers compartidos. Cero mecanismo
  // nuevo: sólo la FK cambia.
  @override
  Future<DeudaData> registrarCargoMantenimientoVehiculo({
    required String deudaId,
    required String vehiculoMantenimientoId,
    required int monto,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _registrarCargo(
      deudaId: deudaId,
      monto: monto,
      fecha: fecha,
      vehiculoMantenimientoId: vehiculoMantenimientoId,
      observaciones: observaciones,
      actorUsuarioId: actorUsuarioId,
    );
  }

  @override
  Future<DeudaData> registrarCargoRecargaLineaTelefonica({
    required String deudaId,
    required String recargaLineaTelefonicaId,
    required int monto,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _registrarCargo(
      deudaId: deudaId,
      monto: monto,
      fecha: fecha,
      recargaLineaTelefonicaId: recargaLineaTelefonicaId,
      observaciones: observaciones,
      actorUsuarioId: actorUsuarioId,
    );
  }

  @override
  Future<DeudaData> registrarCargoCoberturaServicioEventual({
    required String deudaId,
    required String coberturaId,
    required int monto,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _registrarCargo(
      deudaId: deudaId,
      monto: monto,
      fecha: fecha,
      servicioEventualCoberturaId: coberturaId,
      observaciones: observaciones,
      actorUsuarioId: actorUsuarioId,
    );
  }

  @override
  Future<DeudaData> revertirCargoCoberturaServicioEventual({
    required String deudaId,
    required String coberturaId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _revertirCargo(
      deudaId: deudaId,
      motivo: motivo,
      servicioEventualCoberturaId: coberturaId,
      actorUsuarioId: actorUsuarioId,
    );
  }

  @override
  Future<DeudaData> registrarCargoCostoServicioEventual({
    required String deudaId,
    required String costoId,
    required int monto,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _registrarCargo(
      deudaId: deudaId,
      monto: monto,
      fecha: fecha,
      servicioEventualCostoId: costoId,
      observaciones: observaciones,
      actorUsuarioId: actorUsuarioId,
    );
  }

  @override
  Future<DeudaData> revertirCargoCostoServicioEventual({
    required String deudaId,
    required String costoId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _revertirCargo(
      deudaId: deudaId,
      motivo: motivo,
      servicioEventualCostoId: costoId,
      actorUsuarioId: actorUsuarioId,
    );
  }

  @override
  Future<DeudaData> revertirCargoRecargaLineaTelefonica({
    required String deudaId,
    required String recargaLineaTelefonicaId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _revertirCargo(
      deudaId: deudaId,
      motivo: motivo,
      recargaLineaTelefonicaId: recargaLineaTelefonicaId,
      actorUsuarioId: actorUsuarioId,
    );
  }

  @override
  Future<DeudaData> registrarAjusteCargoRecargaLineaTelefonica({
    required String deudaId,
    required String recargaLineaTelefonicaId,
    required int deltaImporte,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _registrarAjusteCargo(
      deudaId: deudaId,
      deltaImporte: deltaImporte,
      motivo: motivo,
      recargaLineaTelefonicaId: recargaLineaTelefonicaId,
      actorUsuarioId: actorUsuarioId,
    );
  }

  @override
  Future<DeudaData> revertirCargoMantenimientoVehiculo({
    required String deudaId,
    required String vehiculoMantenimientoId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _revertirCargo(
      deudaId: deudaId,
      motivo: motivo,
      vehiculoMantenimientoId: vehiculoMantenimientoId,
      actorUsuarioId: actorUsuarioId,
    );
  }

  @override
  Future<DeudaData> registrarAjusteCargoMantenimientoVehiculo({
    required String deudaId,
    required String vehiculoMantenimientoId,
    required int deltaImporte,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _registrarAjusteCargo(
      deudaId: deudaId,
      deltaImporte: deltaImporte,
      motivo: motivo,
      vehiculoMantenimientoId: vehiculoMantenimientoId,
      actorUsuarioId: actorUsuarioId,
    );
  }

  @override
  Future<DeudaData> registrarCargoCostoAdicional({
    required String deudaId,
    required int costoAdicionalId,
    required int monto,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _registrarCargo(
      deudaId: deudaId,
      monto: monto,
      fecha: fecha,
      costoAdicionalId: costoAdicionalId,
      observaciones: observaciones,
      actorUsuarioId: actorUsuarioId,
    );
  }

  @override
  Future<DeudaData> registrarCargoEgreso({
    required String deudaId,
    required String egresoId,
    required int monto,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _registrarCargo(
      deudaId: deudaId,
      monto: monto,
      fecha: fecha,
      egresoGastoId: egresoId,
      observaciones: observaciones,
      actorUsuarioId: actorUsuarioId,
    );
  }

  @override
  Future<DeudaData> registrarAjusteCargoEgreso({
    required String deudaId,
    required String egresoId,
    required int deltaImporte,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _registrarAjusteCargo(
      deudaId: deudaId,
      deltaImporte: deltaImporte,
      motivo: motivo,
      egresoGastoId: egresoId,
      actorUsuarioId: actorUsuarioId,
    );
  }

  @override
  Future<DeudaData> revertirCargoEgreso({
    required String deudaId,
    required String egresoId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _revertirCargo(deudaId: deudaId, motivo: motivo, egresoGastoId: egresoId, actorUsuarioId: actorUsuarioId);
  }

  @override
  Future<int> netoAportadoPorEgreso({required String deudaId, required String egresoId}) {
    return _calcularNetoAportado(deudaId: deudaId, egresoGastoId: egresoId);
  }

  @override
  Future<DeudaData> registrarAjusteCargoCompra({
    required String deudaId,
    required String compraId,
    required int deltaImporte,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _registrarAjusteCargo(
      deudaId: deudaId,
      deltaImporte: deltaImporte,
      motivo: motivo,
      compraId: compraId,
      actorUsuarioId: actorUsuarioId,
    );
  }

  /// Cuerpo compartido de `revertirCargoCompra`/`revertirCargoTiempoExtra`/
  /// `revertirCargoCostoAdicional` — exactamente uno de
  /// `compraId`/`tiempoExtraId`/`costoAdicionalId` identifica los
  /// movimientos propios a revertir.
  /// Suma el efecto NETO que un ítem (Compra/TiempoExtra/CostoAdicional,
  /// exactamente uno de los 3 filtros no-nulo) tiene hoy sobre el
  /// `saldoActual` de [deudaId] — cargo original + cualquier ajuste
  /// posterior, `ajusteNegativo` restado, todo lo demás sumado. `0` si
  /// el ítem nunca tocó esta Deuda, o si sus movimientos ya se
  /// cancelan entre sí. Compartido por `_revertirCargo` (para saber
  /// cuánto revertir) y por `netoAportadoPorCompra` (para que
  /// `CorregirCompraUseCase` pueda validar crédito disponible de una
  /// corrección de monto EN LA MISMA tarjeta sin comparar ingenuamente
  /// contra el saldo total — ver Etapa 3, "resuelto en dominio").
  Future<int> _calcularNetoAportado({
    required String deudaId,
    String? compraId,
    String? tiempoExtraId,
    int? costoAdicionalId,
    String? egresoGastoId,
    String? vehiculoMantenimientoId,
    String? recargaLineaTelefonicaId,
    String? servicioEventualCoberturaId,
    String? servicioEventualCostoId,
  }) async {
    final query = _db.select(_db.movimientoDeuda)..where((t) => t.deudaId.equals(deudaId));
    if (servicioEventualCoberturaId != null) {
      query.where((t) => t.servicioEventualCoberturaId.equals(servicioEventualCoberturaId));
    }
    if (servicioEventualCostoId != null) {
      query.where((t) => t.servicioEventualCostoId.equals(servicioEventualCostoId));
    }
    if (compraId != null) query.where((t) => t.compraId.equals(compraId));
    if (tiempoExtraId != null) query.where((t) => t.tiempoExtraId.equals(tiempoExtraId));
    if (costoAdicionalId != null) query.where((t) => t.costoAdicionalId.equals(costoAdicionalId));
    if (egresoGastoId != null) query.where((t) => t.egresoGastoId.equals(egresoGastoId));
    if (vehiculoMantenimientoId != null) query.where((t) => t.vehiculoMantenimientoId.equals(vehiculoMantenimientoId));
    if (recargaLineaTelefonicaId != null) {
      query.where((t) => t.recargaLineaTelefonicaId.equals(recargaLineaTelefonicaId));
    }
    final movimientosPropios = await query.get();
    return movimientosPropios.fold<int>(
      0,
      (acc, m) => acc + (m.tipo == TipoMovimientoDeuda.ajusteNegativo.name ? -m.importe : m.importe),
    );
  }

  @override
  Future<int> netoAportadoPorCompra({required String deudaId, required String compraId}) {
    return _calcularNetoAportado(deudaId: deudaId, compraId: compraId);
  }

  Future<DeudaData> _revertirCargo({
    required String deudaId,
    required String motivo,
    String? compraId,
    String? tiempoExtraId,
    int? costoAdicionalId,
    String? egresoGastoId,
    String? vehiculoMantenimientoId,
    String? recargaLineaTelefonicaId,
    String? servicioEventualCoberturaId,
    String? servicioEventualCostoId,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final netoAportado = await _calcularNetoAportado(
        deudaId: deudaId,
        compraId: compraId,
        tiempoExtraId: tiempoExtraId,
        costoAdicionalId: costoAdicionalId,
        egresoGastoId: egresoGastoId,
        vehiculoMantenimientoId: vehiculoMantenimientoId,
        recargaLineaTelefonicaId: recargaLineaTelefonicaId,
      );
      if (netoAportado == 0) return (await obtenerPorId(deudaId))!;

      final deuda = await obtenerPorId(deudaId);
      if (deuda == null) throw StateError('Deuda $deudaId no existe.');

      final saldoAnterior = deuda.saldoActual;
      final saldoPosterior = saldoAnterior - netoAportado;

      await _db.into(_db.movimientoDeuda).insert(
            MovimientoDeudaCompanion.insert(
              deudaId: deudaId,
              fecha: DateTime.now(),
              tipo: TipoMovimientoDeuda.ajusteNegativo.name,
              importe: netoAportado,
              saldoAnterior: saldoAnterior,
              saldoPosterior: saldoPosterior,
              compraId: Value(compraId),
              tiempoExtraId: Value(tiempoExtraId),
              costoAdicionalId: Value(costoAdicionalId),
              egresoGastoId: Value(egresoGastoId),
              vehiculoMantenimientoId: Value(vehiculoMantenimientoId),
              recargaLineaTelefonicaId: Value(recargaLineaTelefonicaId),
              servicioEventualCoberturaId: Value(servicioEventualCoberturaId),
              servicioEventualCostoId: Value(servicioEventualCostoId),
              observaciones: Value(motivo),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );

      await (_db.update(_db.deuda)..where((t) => t.id.equals(deudaId))).write(
        DeudaCompanion(saldoActual: Value(saldoPosterior), updatedAt: Value(DateTime.now())),
      );

      return (await obtenerPorId(deudaId))!;
    });
  }

  @override
  Future<DeudaData> revertirCargoCompra({
    required String deudaId,
    required String compraId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _revertirCargo(deudaId: deudaId, motivo: motivo, compraId: compraId, actorUsuarioId: actorUsuarioId);
  }

  @override
  Future<DeudaData> revertirCargoTiempoExtra({
    required String deudaId,
    required String tiempoExtraId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _revertirCargo(deudaId: deudaId, motivo: motivo, tiempoExtraId: tiempoExtraId, actorUsuarioId: actorUsuarioId);
  }

  @override
  Future<DeudaData> revertirCargoCostoAdicional({
    required String deudaId,
    required int costoAdicionalId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _revertirCargo(deudaId: deudaId, motivo: motivo, costoAdicionalId: costoAdicionalId, actorUsuarioId: actorUsuarioId);
  }

  @override
  Future<DeudaData> registrarAjusteCargoTiempoExtra({
    required String deudaId,
    required String tiempoExtraId,
    required int deltaImporte,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _registrarAjusteCargo(
      deudaId: deudaId,
      deltaImporte: deltaImporte,
      motivo: motivo,
      tiempoExtraId: tiempoExtraId,
      actorUsuarioId: actorUsuarioId,
    );
  }

  @override
  Future<DeudaData> registrarAjusteCargoCostoAdicional({
    required String deudaId,
    required int costoAdicionalId,
    required int deltaImporte,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _registrarAjusteCargo(
      deudaId: deudaId,
      deltaImporte: deltaImporte,
      motivo: motivo,
      costoAdicionalId: costoAdicionalId,
      actorUsuarioId: actorUsuarioId,
    );
  }

  /// Cuerpo compartido de `registrarAjusteCargoCompra`/
  /// `registrarAjusteCargoTiempoExtra`/`registrarAjusteCargoCostoAdicional`/
  /// `registrarAjusteCargoEgreso` — mismo patrón de generalización que
  /// `_registrarCargo`/`_revertirCargo`.
  Future<DeudaData> _registrarAjusteCargo({
    required String deudaId,
    required int deltaImporte,
    required String motivo,
    String? compraId,
    String? tiempoExtraId,
    int? costoAdicionalId,
    String? egresoGastoId,
    String? vehiculoMantenimientoId,
    String? recargaLineaTelefonicaId,
    String? servicioEventualCoberturaId,
    String? servicioEventualCostoId,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      if (deltaImporte == 0) return (await obtenerPorId(deudaId))!;

      final deuda = await obtenerPorId(deudaId);
      if (deuda == null) throw StateError('Deuda $deudaId no existe.');

      final saldoAnterior = deuda.saldoActual;
      final saldoPosterior = saldoAnterior + deltaImporte;

      await _db.into(_db.movimientoDeuda).insert(
            MovimientoDeudaCompanion.insert(
              deudaId: deudaId,
              fecha: DateTime.now(),
              tipo: deltaImporte > 0 ? TipoMovimientoDeuda.ajustePositivo.name : TipoMovimientoDeuda.ajusteNegativo.name,
              importe: deltaImporte.abs(),
              saldoAnterior: saldoAnterior,
              saldoPosterior: saldoPosterior,
              compraId: Value(compraId),
              tiempoExtraId: Value(tiempoExtraId),
              costoAdicionalId: Value(costoAdicionalId),
              egresoGastoId: Value(egresoGastoId),
              vehiculoMantenimientoId: Value(vehiculoMantenimientoId),
              recargaLineaTelefonicaId: Value(recargaLineaTelefonicaId),
              servicioEventualCoberturaId: Value(servicioEventualCoberturaId),
              servicioEventualCostoId: Value(servicioEventualCostoId),
              observaciones: Value(motivo),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );

      await (_db.update(_db.deuda)..where((t) => t.id.equals(deudaId))).write(
        DeudaCompanion(saldoActual: Value(saldoPosterior), updatedAt: Value(DateTime.now())),
      );

      return (await obtenerPorId(deudaId))!;
    });
  }

  /// Filtro combinado (pago base + cualquier costo adicional) usado por
  /// `detalleBloqueoEliminacionCargoTiempoExtra`/
  /// `eliminarCargoTiempoExtraFisicamente`.
  Expression<bool> _filtroMovimientosTiempoExtra(String tiempoExtraId, List<int> costoAdicionalIds) {
    var expr = _db.movimientoDeuda.tiempoExtraId.equals(tiempoExtraId);
    if (costoAdicionalIds.isNotEmpty) {
      expr = expr | _db.movimientoDeuda.costoAdicionalId.isIn(costoAdicionalIds);
    }
    return expr;
  }

  @override
  Future<String?> detalleBloqueoEliminacionCargoTiempoExtra({
    required String tiempoExtraId,
    required List<int> costoAdicionalIds,
  }) async {
    final propios = await (_db.select(_db.movimientoDeuda)
          ..where((t) => _filtroMovimientosTiempoExtra(tiempoExtraId, costoAdicionalIds)))
        .get();
    if (propios.isEmpty) return null;

    final porDeuda = <String, List<MovimientoDeudaData>>{};
    for (final m in propios) {
      porDeuda.putIfAbsent(m.deudaId, () => []).add(m);
    }

    for (final entrada in porDeuda.entries) {
      final todos = await (_db.select(_db.movimientoDeuda)
            ..where((t) => t.deudaId.equals(entrada.key))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();
      final primerIdPropio = entrada.value.map((m) => m.id).reduce((a, b) => a < b ? a : b);
      final posterioresOIguales = todos.where((m) => m.id >= primerIdPropio).length;
      if (posterioresOIguales != entrada.value.length) {
        return 'Una tarjeta involucrada en esta cobertura ya tiene movimientos posteriores — no puede '
            'eliminarse sin dejar su historial inconsistente.';
      }
    }
    return null;
  }

  @override
  Future<void> eliminarCargoTiempoExtraFisicamente({
    required String tiempoExtraId,
    required List<int> costoAdicionalIds,
  }) async {
    final movimientos = await (_db.select(_db.movimientoDeuda)
          ..where((t) => _filtroMovimientosTiempoExtra(tiempoExtraId, costoAdicionalIds))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    if (movimientos.isEmpty) return;

    final porDeuda = <String, List<MovimientoDeudaData>>{};
    for (final m in movimientos) {
      porDeuda.putIfAbsent(m.deudaId, () => []).add(m);
    }

    for (final entrada in porDeuda.entries) {
      final saldoRestaurado = entrada.value.first.saldoAnterior;
      for (final m in entrada.value) {
        await (_db.delete(_db.movimientoDeuda)..where((t) => t.id.equals(m.id))).go();
      }
      await (_db.update(_db.deuda)..where((t) => t.id.equals(entrada.key)))
          .write(DeudaCompanion(saldoActual: Value(saldoRestaurado), updatedAt: Value(DateTime.now())));
    }
  }

  // Etapa 3 (Compras — corrección financiera completa Cuenta↔TDC): una
  // Compra corregida con transiciones D/E/F puede tener movimientos en
  // MÁS DE UNA `Deuda` a lo largo de su historia (o movimientos en una
  // tarjeta aunque su `deudaId` VIGENTE ya sea `null`, tras una
  // transición TDC→Cuenta). El chequeo/borrado ya no puede asumir "una
  // sola tarjeta" — agrupa por `deudaId` exactamente igual que
  // [detalleBloqueoEliminacionCargoTiempoExtra]/
  // [eliminarCargoTiempoExtraFisicamente], su mismo precedente real.
  @override
  Future<String?> detalleBloqueoEliminacionCargoCompra(String compraId) async {
    final propios = await (_db.select(_db.movimientoDeuda)..where((t) => t.compraId.equals(compraId))).get();
    if (propios.isEmpty) return null;

    final porDeuda = <String, List<MovimientoDeudaData>>{};
    for (final m in propios) {
      porDeuda.putIfAbsent(m.deudaId, () => []).add(m);
    }

    for (final entrada in porDeuda.entries) {
      final todos = await (_db.select(_db.movimientoDeuda)
            ..where((t) => t.deudaId.equals(entrada.key))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();
      final primerIdPropio = entrada.value.map((m) => m.id).reduce((a, b) => a < b ? a : b);
      final posterioresOIguales = todos.where((m) => m.id >= primerIdPropio).length;
      if (posterioresOIguales != entrada.value.length) {
        return 'Una tarjeta que financió esta Compra en algún momento de su historial ya tiene movimientos '
            'posteriores — no puede eliminarse sin dejar el historial de esa tarjeta inconsistente.';
      }
    }
    return null;
  }

  @override
  Future<void> eliminarCargoCompraFisicamente(String compraId) async {
    final movimientos = await (_db.select(_db.movimientoDeuda)..where((t) => t.compraId.equals(compraId))).get();
    if (movimientos.isEmpty) return;

    final porDeuda = <String, List<MovimientoDeudaData>>{};
    for (final m in movimientos) {
      porDeuda.putIfAbsent(m.deudaId, () => []).add(m);
    }

    for (final entrada in porDeuda.entries) {
      final ordenados = [...entrada.value]..sort((a, b) => a.id.compareTo(b.id));
      final saldoRestaurado = ordenados.first.saldoAnterior;
      for (final m in ordenados) {
        await (_db.delete(_db.movimientoDeuda)..where((t) => t.id.equals(m.id))).go();
      }
      await (_db.update(_db.deuda)..where((t) => t.id.equals(entrada.key)))
          .write(DeudaCompanion(saldoActual: Value(saldoRestaurado), updatedAt: Value(DateTime.now())));
    }
  }

  @override
  Future<DeudaData> cancelar({
    required String deudaId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final deuda = await obtenerPorId(deudaId);
      if (deuda == null) throw StateError('Deuda $deudaId no existe.');

      await _db.into(_db.movimientoDeuda).insert(
            MovimientoDeudaCompanion.insert(
              deudaId: deudaId,
              fecha: DateTime.now(),
              tipo: TipoMovimientoDeuda.cancelacion.name,
              importe: deuda.saldoActual == 0 ? 1 : deuda.saldoActual,
              saldoAnterior: deuda.saldoActual,
              saldoPosterior: 0,
              observaciones: Value(motivo),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );

      await (_db.update(_db.deuda)..where((t) => t.id.equals(deudaId))).write(
        DeudaCompanion(
          saldoActual: const Value(0),
          estatus: Value(EstatusDeuda.cancelada.name),
          motivoCancelacion: Value(motivo),
          updatedAt: Value(DateTime.now()),
        ),
      );

      return (await obtenerPorId(deudaId))!;
    });
  }

  @override
  Future<ResumenEliminacionDeuda> obtenerResumenEliminacionFisica(String deudaId) async {
    final deuda = await obtenerPorId(deudaId);
    if (deuda == null) return const ResumenEliminacionDeuda(existe: false);

    // Etapa 19B: a diferencia de `MovimientoDeuda`/`Egreso` (propiedad
    // exclusiva de la Deuda), una Compra referencia la tarjeta vía
    // `Compra.deudaId` (`restrict`) — sin este chequeo, el `DELETE`
    // fallaría con una violación de FK cruda en vez de un mensaje claro.
    final comprasFinanciadas = await (_db.select(_db.compra)..where((t) => t.deudaId.equals(deudaId))).get();
    if (comprasFinanciadas.isNotEmpty) {
      return ResumenEliminacionDeuda(
        existe: true,
        detalleBloqueo:
            'Esta tarjeta financió ${comprasFinanciadas.length} Compra(s) (ej. ${comprasFinanciadas.first.folioCompra}) — '
            'no puede eliminarse mientras existan.',
      );
    }

    // `MovimientoDeuda`/sus `Egreso` son propiedad exclusiva de la
    // Deuda (ver el doc comment de la interfaz) — no hay más bloqueo
    // real que verificar.
    return const ResumenEliminacionDeuda(existe: true);
  }

  @override
  Future<EliminarDeudaFisicamenteResultado> eliminarFisicamente({
    required String deudaId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final deuda = await obtenerPorId(deudaId);
    if (deuda == null) return EliminarDeudaFisicamenteNoExiste();

    await _db.transaction(() async {
      final movimientos = await listarMovimientos(deudaId);
      final egresoIds = {for (final m in movimientos) if (m.egresoId != null) m.egresoId!};
      final egresos = <EgresoData>[];
      for (final id in egresoIds) {
        final egreso = await (_db.select(_db.egreso)..where((t) => t.id.equals(id))).getSingleOrNull();
        if (egreso != null) egresos.add(egreso);
      }

      final snapshot = <String, Object?>{
        'deuda': deuda.toJson(),
        'movimientos': [for (final m in movimientos) m.toJson()],
        'egresos': [for (final e in egresos) e.toJson()],
      };

      await _db.into(_db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'deuda',
              entidadIdOriginal: deudaId,
              fechaHora: DateTime.now(),
              motivo: motivo,
              actorUsuarioId: Value(actorUsuarioId),
              snapshotJson: jsonEncode(snapshot),
            ),
          );

      // Borra la Deuda — cascada automática borra todos sus
      // `MovimientoDeuda` (libera la referencia `restrict` hacia cada
      // Egreso). Los Egresos recolectados se borran después, nunca
      // antes: `MovimientoDeuda.egresoId` es `restrict`.
      await (_db.delete(_db.deuda)..where((t) => t.id.equals(deudaId))).go();
      for (final egreso in egresos) {
        await (_db.delete(_db.egreso)..where((t) => t.id.equals(egreso.id))).go();
      }
    });

    return EliminarDeudaFisicamenteExitoso();
  }
}
