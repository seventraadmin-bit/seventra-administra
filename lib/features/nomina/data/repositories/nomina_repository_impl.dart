import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/descuentos_personal/domain/repositories/descuento_programado_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/asignacion_repository.dart';
import 'package:riseg_one/features/tiempos_extra/domain/repositories/tiempo_extra_repository.dart';

import '../../domain/repositories/nomina_repository.dart';
import '../../domain/repositories/pago_nomina_repository.dart';
import '../../domain/usecases/calcular_periodo_nomina.dart';
import '../../domain/usecases/calcular_totales_renglon_nomina.dart';
import '../../domain/usecases/eliminar_cadena_prueba_nomina_usecase.dart';
import '../../domain/usecases/eliminar_nomina_fisicamente_usecase.dart';
import '../../domain/usecases/fila_nomina_generada.dart';
import '../tables/nomina_table.dart' show TipoPeriodoNomina;

/// Compone con `AsignacionRepository` real (Inventario, dominio ajeno)
/// para aplicar `DescuentoInventario` pendientes al generar, y con
/// `DescuentoProgramadoRepository` (Etapa 15, "Descuentos Programados
/// al Personal" — préstamos/botas) para resolver/reservar/liberar
/// cuotas — mismo criterio "repositorio compone repositorio" que ya usa
/// `PagoNominaRepositoryImpl` con `EgresoRepository` (Finanzas).
///
/// También compone `PagoNominaRepository` (bug real reportado por
/// Marlon, 2026-08-30): un renglón cuyo `totalAPagar` recalculado da
/// `0` nunca pasa por un pago real (no hay nada que pagar), así que su
/// `estatusPago` se quedaba atorado en `pendiente` para siempre — y
/// eso a su vez dejaba la Nómina completa atorada en `cerrada`
/// (`_evaluarNominaPagada` exige que TODOS los renglones reporten
/// `pagado`), por lo que seguía apareciendo como "Próxima nómina" en
/// el Dashboard aun después de pagarla. `sincronizarEstatusPago` se
/// invoca después de cada escritura de `totalAPagar` para que ese
/// renglón siempre refleje su estatus real, incluyendo el efecto
/// secundario sobre `DescuentoProgramadoCuota` (`reservada` ⇄
/// `aplicada`) — mismo criterio que un pago real.
class NominaRepositoryImpl implements NominaRepository {
  NominaRepositoryImpl(
    this._db,
    this._asignacionRepository,
    this._descuentoProgramadoRepository,
    this._tiempoExtraRepository,
    this._pagoNominaRepository,
  );

  final AppDatabase _db;
  final AsignacionRepository _asignacionRepository;
  final DescuentoProgramadoRepository _descuentoProgramadoRepository;
  final TiempoExtraRepository _tiempoExtraRepository;
  final PagoNominaRepository _pagoNominaRepository;

  @override
  Future<NominaData?> obtenerPorId(String id) {
    return (_db.select(_db.nomina)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<NominaData?> obtenerPorPeriodo({required int anio, required int mes, required TipoPeriodoNomina tipo}) {
    return (_db.select(_db.nomina)
          ..where((t) => t.anio.equals(anio) & t.mes.equals(mes) & t.tipoPeriodo.equals(tipo.name)))
        .getSingleOrNull();
  }

  @override
  Future<List<NominaData>> listar() {
    return (_db.select(_db.nomina)
          ..orderBy([(t) => OrderingTerm.desc(t.anio), (t) => OrderingTerm.desc(t.mes), (t) => OrderingTerm.desc(t.tipoPeriodo)]))
        .get();
  }

  @override
  Future<List<NominaData>> listarEnRango({DateTime? rangoInicio, DateTime? rangoFin, String? estatus}) {
    final query = _db.select(_db.nomina);
    if (rangoInicio != null) query.where((t) => t.fechaFinPeriodo.isBiggerOrEqualValue(rangoInicio));
    if (rangoFin != null) query.where((t) => t.fechaInicioPeriodo.isSmallerOrEqualValue(rangoFin));
    if (estatus != null) query.where((t) => t.estatus.equals(estatus));
    query.orderBy([(t) => OrderingTerm.desc(t.fechaInicioPeriodo)]);
    return query.get();
  }

  @override
  Future<List<NominaEmpleadoReporteRow>> listarRenglonesEnRango({
    DateTime? rangoInicio,
    DateTime? rangoFin,
    String? estatus,
  }) async {
    final query = _db.selectOnly(_db.nominaEmpleado).join([
      innerJoin(_db.nomina, _db.nomina.id.equalsExp(_db.nominaEmpleado.nominaId)),
    ])
      ..addColumns([
        _db.nominaEmpleado.id,
        _db.nominaEmpleado.nominaId,
        _db.nominaEmpleado.numeroEmpleado,
        _db.nominaEmpleado.nombreCompleto,
        _db.nominaEmpleado.puestoNombre,
        _db.nominaEmpleado.servicioId,
        _db.nominaEmpleado.servicioNombre,
        _db.nominaEmpleado.turnoNombre,
        _db.nominaEmpleado.importeBase,
        _db.nominaEmpleado.bono,
        _db.nominaEmpleado.faltas,
        _db.nominaEmpleado.descuentoPorFaltas,
        _db.nominaEmpleado.prestamo,
        _db.nominaEmpleado.tiempoExtra,
        _db.nominaEmpleado.otrosDescuentos,
        _db.nominaEmpleado.montoFiscal,
        _db.nominaEmpleado.montoNoFiscal,
        _db.nominaEmpleado.totalAPagar,
        _db.nominaEmpleado.estatusPago,
      ]);
    if (rangoInicio != null) query.where(_db.nomina.fechaFinPeriodo.isBiggerOrEqualValue(rangoInicio));
    if (rangoFin != null) query.where(_db.nomina.fechaInicioPeriodo.isSmallerOrEqualValue(rangoFin));
    if (estatus != null) query.where(_db.nomina.estatus.equals(estatus));

    final filas = await query.get();
    return [
      for (final fila in filas)
        NominaEmpleadoReporteRow(
          id: fila.read(_db.nominaEmpleado.id)!,
          nominaId: fila.read(_db.nominaEmpleado.nominaId)!,
          numeroEmpleado: fila.read(_db.nominaEmpleado.numeroEmpleado)!,
          nombreCompleto: fila.read(_db.nominaEmpleado.nombreCompleto)!,
          puestoNombre: fila.read(_db.nominaEmpleado.puestoNombre),
          servicioId: fila.read(_db.nominaEmpleado.servicioId),
          servicioNombre: fila.read(_db.nominaEmpleado.servicioNombre),
          turnoNombre: fila.read(_db.nominaEmpleado.turnoNombre),
          importeBase: fila.read(_db.nominaEmpleado.importeBase)!,
          bono: fila.read(_db.nominaEmpleado.bono)!,
          faltas: fila.read(_db.nominaEmpleado.faltas)!,
          descuentoPorFaltas: fila.read(_db.nominaEmpleado.descuentoPorFaltas)!,
          prestamo: fila.read(_db.nominaEmpleado.prestamo)!,
          tiempoExtra: fila.read(_db.nominaEmpleado.tiempoExtra)!,
          otrosDescuentos: fila.read(_db.nominaEmpleado.otrosDescuentos)!,
          montoFiscal: fila.read(_db.nominaEmpleado.montoFiscal)!,
          montoNoFiscal: fila.read(_db.nominaEmpleado.montoNoFiscal)!,
          totalAPagar: fila.read(_db.nominaEmpleado.totalAPagar)!,
          estatusPago: fila.read(_db.nominaEmpleado.estatusPago)!,
        ),
    ];
  }

  @override
  Future<List<NominaEmpleadoData>> listarEmpleados(String nominaId) {
    return (_db.select(_db.nominaEmpleado)
          ..where((t) => t.nominaId.equals(nominaId))
          ..orderBy([(t) => OrderingTerm.asc(t.numeroEmpleado)]))
        .get();
  }

  @override
  Future<NominaEmpleadoData?> obtenerEmpleado(String nominaEmpleadoId) {
    return (_db.select(_db.nominaEmpleado)..where((t) => t.id.equals(nominaEmpleadoId))).getSingleOrNull();
  }

  @override
  Future<NominaEmpleadoData?> obtenerEmpleadoPorNominaYEmpleado({required String nominaId, required String empleadoId}) {
    return (_db.select(_db.nominaEmpleado)
          ..where((t) => t.nominaId.equals(nominaId) & t.empleadoId.equals(empleadoId)))
        .getSingleOrNull();
  }

  @override
  Future<List<NominaEmpleadoTramoData>> listarTramos(String nominaEmpleadoId) {
    return (_db.select(_db.nominaEmpleadoTramo)
          ..where((t) => t.nominaEmpleadoId.equals(nominaEmpleadoId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaInicio)]))
        .get();
  }

  @override
  Future<List<NominaEmpleadoAusenciaData>> listarAusencias(String nominaEmpleadoId) {
    return (_db.select(_db.nominaEmpleadoAusencia)
          ..where((t) => t.nominaEmpleadoId.equals(nominaEmpleadoId))
          ..orderBy([(t) => OrderingTerm.asc(t.fecha)]))
        .get();
  }

  @override
  Future<List<NominaEventoData>> listarEventos(String nominaId) {
    return (_db.select(_db.nominaEvento)
          ..where((t) => t.nominaId.equals(nominaId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaHora)]))
        .get();
  }

  /// Determina qué `DescuentoInventario` PENDIENTES de [empleadoId]
  /// caben dentro de [netoDisponible] sin dejarlo negativo (Etapa 15,
  /// resolución explícita de Marlon: "bloquear y avisar" — nunca un
  /// `totalAPagar` negativo silencioso). Orden FIFO por fecha de
  /// creación: se aplican los más antiguos primero, hasta donde
  /// alcance; el resto queda `pendiente` para una Nómina futura y
  /// `pendienteRevision` queda en `true` (bloquea `CerrarNominaUseCase`,
  /// mismo criterio que `distribucionPendienteRevision`). Solo lectura
  /// — no aplica nada, el llamador decide cuándo (necesita el
  /// `nominaEmpleadoId` real, que no existe hasta insertar/actualizar
  /// el renglón).
  Future<({int suma, List<String> ids, bool pendienteRevision})> _resolverDescuentosAplicables({
    required String empleadoId,
    required int netoDisponible,
  }) async {
    final pendientes = await _asignacionRepository.listarDescuentosPendientesPorEmpleado(empleadoId);
    if (pendientes.isEmpty) return (suma: 0, ids: const <String>[], pendienteRevision: false);

    final ordenados = [...pendientes]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    var suma = 0;
    final ids = <String>[];
    for (final d in ordenados) {
      if (suma + d.importe > netoDisponible) break;
      suma += d.importe;
      ids.add(d.id);
    }
    return (suma: suma, ids: ids, pendienteRevision: ids.length < ordenados.length);
  }

  Future<void> _aplicarDescuentosResueltos({
    required List<String> ids,
    required String nominaEmpleadoId,
  }) {
    if (ids.isEmpty) return Future.value();
    return _asignacionRepository.aplicarDescuentos(descuentoIds: ids, nominaEmpleadoId: nominaEmpleadoId, fechaAplicacion: DateTime.now());
  }

  /// Determina qué `DescuentoProgramadoCuota` PENDIENTES de [empleadoId]
  /// caben dentro de [netoDisponible] sin dejarlo negativo — mismo
  /// criterio exacto que [_resolverDescuentosAplicables], con dos
  /// diferencias deliberadas: (1) el orden FIFO es por
  /// `fechaProgramada` (la fecha del plan), no `createdAt` — una cuota
  /// reprogramada a una fecha más próxima debe recuperarse antes,
  /// aunque su fila sea más nueva; (2) **nunca incorpora una cuota
  /// futura**: se descartan antes de la resolución todas las
  /// `fechaProgramada` posteriores a [fechaCorte] (la fecha de pago de
  /// la Nómina que se está resolviendo) — "Generar Nómina no incorpora
  /// cuota futura" es un requisito explícito, no un efecto secundario
  /// del cabe-en-el-neto.
  Future<({int suma, List<String> ids, bool pendienteRevision})> _resolverCuotasProgramadasAplicables({
    required String empleadoId,
    required int netoDisponible,
    required DateTime fechaCorte,
  }) async {
    final pendientes = await _descuentoProgramadoRepository.listarCuotasPendientesPorEmpleado(empleadoId);
    final elegibles = pendientes.where((c) => !c.fechaProgramada.isAfter(fechaCorte)).toList();
    if (elegibles.isEmpty) return (suma: 0, ids: const <String>[], pendienteRevision: false);

    final ordenados = [...elegibles]..sort((a, b) => a.fechaProgramada.compareTo(b.fechaProgramada));
    var suma = 0;
    final ids = <String>[];
    for (final c in ordenados) {
      if (suma + c.importeProgramado > netoDisponible) break;
      suma += c.importeProgramado;
      ids.add(c.id);
    }
    return (suma: suma, ids: ids, pendienteRevision: ids.length < ordenados.length);
  }

  /// Única fuente de verdad de Fiscal/No fiscal (Etapa 15, bug real:
  /// un descuento de Inventario aplicado al generar dejaba `montoFiscal`
  /// congelado en el neto ANTES de restarlo, rompiendo la invariante
  /// `montoFiscal + montoNoFiscal == totalAPagar`). [totalAPagar] debe
  /// ser siempre el neto FINAL — después de percepciones y TODAS las
  /// deducciones, incluido `descuentosInventario` — nunca un total
  /// parcial calculado antes de resolver los descuentos.
  ///
  /// Regla (Resolución explícita de Marlon, ya vigente en
  /// `ActualizarNominaDesdePersonalUseCase` pero con el total
  /// equivocado, y ausente por completo en `actualizarMovimientos`):
  /// si la distribución nunca se modificó a mano, se reinicia al
  /// default (100% Fiscal). Si sí se modificó a mano, se conserva
  /// **siempre** tal cual — pero si [totalAPagar] ya no coincide con
  /// esa distribución conservada, se marca `pendienteRevision` (bloquea
  /// `CerrarNominaUseCase`) en vez de ajustarla en silencio o repartir
  /// la diferencia — nunca se asume dónde debe ir un cambio de neto.
  ///
  /// Usado por [_insertarRenglon]/[_actualizarRenglonExistente]
  /// (ambos ya conocen el `totalAPagar` final en el momento en que se
  /// llama) y por [actualizarMovimientos] — un solo lugar, para que
  /// ninguna otra modificación futura del renglón repita el mismo bug.
  ({int montoFiscal, int montoNoFiscal, bool pendienteRevision}) _resolverDistribucionFiscal({
    required int totalAPagar,
    required bool distribucionModificadaManualmente,
    required int montoFiscalPrevio,
    required int montoNoFiscalPrevio,
  }) {
    if (!distribucionModificadaManualmente) {
      return (montoFiscal: totalAPagar, montoNoFiscal: 0, pendienteRevision: false);
    }
    final cuadra = montoFiscalPrevio + montoNoFiscalPrevio == totalAPagar;
    return (montoFiscal: montoFiscalPrevio, montoNoFiscal: montoNoFiscalPrevio, pendienteRevision: !cuadra);
  }

  Future<NominaEmpleadoData> _insertarRenglon({
    required String nominaId,
    required FilaNominaGenerada datos,
    required int prestamo,
    required int tiempoExtra,
    required int bono,
    required bool bonoModificadoManualmente,
    required int faltas,
    required int otrosDescuentos,
    required int descuentosInventario,
    required bool descuentosInventarioPendienteRevision,
    required int descuentosProgramados,
    required bool descuentosProgramadosPendienteRevision,
    required String? observaciones,
  }) async {
    final pagoPorDia = (datos.sueldoMensualUtilizado / 30).round();
    final totales = calcularTotalesRenglonNomina(
      importeBase: datos.importeBase,
      pagoPorDia: pagoPorDia,
      bono: bono,
      tiempoExtra: tiempoExtra,
      prestamo: prestamo,
      faltas: faltas,
      otrosDescuentos: otrosDescuentos,
      descuentosInventario: descuentosInventario,
      descuentosProgramados: descuentosProgramados,
    );
    final descuentoPorFaltas = totales.descuentoPorFaltas;
    final totalAPagar = totales.totalAPagar;
    // Renglón nuevo: nunca hay una distribución previa que preservar —
    // siempre el default 100% Fiscal (ver el doc comment de
    // `_resolverDistribucionFiscal`).
    final distribucion = _resolverDistribucionFiscal(
      totalAPagar: totalAPagar,
      distribucionModificadaManualmente: false,
      montoFiscalPrevio: 0,
      montoNoFiscalPrevio: 0,
    );

    final renglon = await _db.into(_db.nominaEmpleado).insertReturning(
          NominaEmpleadoCompanion.insert(
            nominaId: nominaId,
            empleadoId: datos.empleadoId,
            numeroEmpleado: datos.numeroEmpleado,
            nombreCompleto: datos.nombreCompleto,
            puestoNombre: Value(datos.puestoNombre),
            servicioId: Value(datos.servicioId),
            servicioNombre: Value(datos.servicioNombre),
            turnoNombre: Value(datos.turnoNombre),
            bancoNombre: Value(datos.bancoNombre),
            numeroCuentaTarjeta: Value(datos.numeroCuentaTarjeta),
            clabe: Value(datos.clabe),
            fuenteSueldoUtilizada: datos.fuenteSueldoUtilizada.name,
            diasPagables: datos.diasPagables,
            sueldoMensualUtilizado: datos.sueldoMensualUtilizado,
            sueldoQuincenalReferencia: (datos.sueldoMensualUtilizado / 2).round(),
            pagoPorDia: pagoPorDia,
            importeBase: datos.importeBase,
            prestamo: Value(prestamo),
            tiempoExtra: Value(tiempoExtra),
            bono: Value(bono),
            bonoModificadoManualmente: Value(bonoModificadoManualmente),
            faltas: Value(faltas),
            descuentoPorFaltas: Value(descuentoPorFaltas),
            otrosDescuentos: Value(otrosDescuentos),
            descuentosInventario: Value(descuentosInventario),
            descuentosInventarioPendienteRevision: Value(descuentosInventarioPendienteRevision),
            descuentosProgramados: Value(descuentosProgramados),
            descuentosProgramadosPendienteRevision: Value(descuentosProgramadosPendienteRevision),
            observaciones: Value(observaciones),
            montoFiscal: Value(distribucion.montoFiscal),
            montoNoFiscal: Value(distribucion.montoNoFiscal),
            distribucionModificadaManualmente: const Value(false),
            distribucionPendienteRevision: Value(distribucion.pendienteRevision),
            totalAPagar: totalAPagar,
          ),
        );

    for (final tramo in datos.tramos) {
      await _db.into(_db.nominaEmpleadoTramo).insert(
            NominaEmpleadoTramoCompanion.insert(
              nominaEmpleadoId: renglon.id,
              fechaInicio: tramo.fechaInicio,
              fechaFin: tramo.fechaFin,
              servicioId: Value(tramo.servicioId),
              servicioNombre: Value(tramo.servicioNombre),
              turnoNombre: Value(tramo.turnoNombre),
              fuenteSueldo: tramo.fuente.name,
              sueldoMensual: tramo.sueldoMensual,
              bonoMensual: tramo.bonoMensual,
              diasReales: tramo.diasReales,
              importeTramo: tramo.importeTramo,
            ),
          );
    }

    return renglon;
  }

  /// Actualiza EN SU LUGAR un renglón ya existente — nunca lo borra y
  /// lo vuelve a crear (a diferencia del `_insertarRenglon` original de
  /// antes de esta ampliación): un renglón con `DescuentoInventario`
  /// ya aplicado no puede pasar por un `DELETE` (la FK `restrict` de
  /// `DescuentoInventario.nominaEmpleadoId` lo rechazaría), y
  /// "Actualizar desde Personal" debe poder correr repetidamente sin
  /// romperse solo porque ese Empleado ya tuvo un descuento aplicado en
  /// una corrida anterior. Solo los tramos se reemplazan por completo
  /// (nada los referencia desde afuera).
  Future<NominaEmpleadoData> _actualizarRenglonExistente({
    required NominaEmpleadoData existente,
    required FilaNominaGenerada datos,
    required int prestamo,
    required int tiempoExtra,
    required int bono,
    required bool bonoModificadoManualmente,
    required int faltas,
    required int otrosDescuentos,
    required int descuentosInventario,
    required bool descuentosInventarioPendienteRevision,
    required int descuentosProgramados,
    required bool descuentosProgramadosPendienteRevision,
    required String? observaciones,
  }) async {
    final nominaEmpleadoId = existente.id;
    final pagoPorDia = (datos.sueldoMensualUtilizado / 30).round();
    final totales = calcularTotalesRenglonNomina(
      importeBase: datos.importeBase,
      pagoPorDia: pagoPorDia,
      bono: bono,
      tiempoExtra: tiempoExtra,
      prestamo: prestamo,
      faltas: faltas,
      otrosDescuentos: otrosDescuentos,
      descuentosInventario: descuentosInventario,
      descuentosProgramados: descuentosProgramados,
    );
    final descuentoPorFaltas = totales.descuentoPorFaltas;
    final totalAPagar = totales.totalAPagar;
    final distribucion = _resolverDistribucionFiscal(
      totalAPagar: totalAPagar,
      distribucionModificadaManualmente: existente.distribucionModificadaManualmente,
      montoFiscalPrevio: existente.montoFiscal,
      montoNoFiscalPrevio: existente.montoNoFiscal,
    );

    await (_db.update(_db.nominaEmpleado)..where((t) => t.id.equals(nominaEmpleadoId))).write(
      NominaEmpleadoCompanion(
        numeroEmpleado: Value(datos.numeroEmpleado),
        nombreCompleto: Value(datos.nombreCompleto),
        puestoNombre: Value(datos.puestoNombre),
        servicioId: Value(datos.servicioId),
        servicioNombre: Value(datos.servicioNombre),
        turnoNombre: Value(datos.turnoNombre),
        bancoNombre: Value(datos.bancoNombre),
        numeroCuentaTarjeta: Value(datos.numeroCuentaTarjeta),
        clabe: Value(datos.clabe),
        fuenteSueldoUtilizada: Value(datos.fuenteSueldoUtilizada.name),
        diasPagables: Value(datos.diasPagables),
        sueldoMensualUtilizado: Value(datos.sueldoMensualUtilizado),
        sueldoQuincenalReferencia: Value((datos.sueldoMensualUtilizado / 2).round()),
        pagoPorDia: Value(pagoPorDia),
        importeBase: Value(datos.importeBase),
        prestamo: Value(prestamo),
        tiempoExtra: Value(tiempoExtra),
        bono: Value(bono),
        bonoModificadoManualmente: Value(bonoModificadoManualmente),
        faltas: Value(faltas),
        descuentoPorFaltas: Value(descuentoPorFaltas),
        otrosDescuentos: Value(otrosDescuentos),
        descuentosInventario: Value(descuentosInventario),
        descuentosInventarioPendienteRevision: Value(descuentosInventarioPendienteRevision),
        descuentosProgramados: Value(descuentosProgramados),
        descuentosProgramadosPendienteRevision: Value(descuentosProgramadosPendienteRevision),
        observaciones: Value(observaciones),
        montoFiscal: Value(distribucion.montoFiscal),
        montoNoFiscal: Value(distribucion.montoNoFiscal),
        distribucionPendienteRevision: Value(distribucion.pendienteRevision),
        totalAPagar: Value(totalAPagar),
        updatedAt: Value(DateTime.now()),
      ),
    );

    await (_db.delete(_db.nominaEmpleadoTramo)..where((t) => t.nominaEmpleadoId.equals(nominaEmpleadoId))).go();
    for (final tramo in datos.tramos) {
      await _db.into(_db.nominaEmpleadoTramo).insert(
            NominaEmpleadoTramoCompanion.insert(
              nominaEmpleadoId: nominaEmpleadoId,
              fechaInicio: tramo.fechaInicio,
              fechaFin: tramo.fechaFin,
              servicioId: Value(tramo.servicioId),
              servicioNombre: Value(tramo.servicioNombre),
              turnoNombre: Value(tramo.turnoNombre),
              fuenteSueldo: tramo.fuente.name,
              sueldoMensual: tramo.sueldoMensual,
              bonoMensual: tramo.bonoMensual,
              diasReales: tramo.diasReales,
              importeTramo: tramo.importeTramo,
            ),
          );
    }

    return (_db.select(_db.nominaEmpleado)..where((t) => t.id.equals(nominaEmpleadoId))).getSingle();
  }

  @override
  Future<NominaData> generar({
    required String folio,
    required PeriodoNomina periodo,
    required List<FilaNominaGenerada> filas,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final nomina = await _db.into(_db.nomina).insertReturning(
            NominaCompanion.insert(
              folio: folio,
              anio: periodo.anio,
              mes: periodo.mes,
              tipoPeriodo: periodo.tipo.name,
              fechaInicioPeriodo: periodo.fechaInicio,
              fechaFinPeriodo: periodo.fechaFin,
              fechaPagoOrdinaria: periodo.fechaPago,
            ),
          );

      for (final fila in filas) {
        // Pendiente → Aplicado (Etapa 15, integración real con Nómina):
        // cualquier `DescuentoInventario` todavía `pendiente` de este
        // Empleado se aplica en el renglón que se está generando —
        // "la siguiente Nómina aplicable", hasta donde el neto alcance
        // (Resolución explícita de Marlon: "bloquear y avisar", nunca
        // un total negativo silencioso — ver `_resolverDescuentosAplicables`).
        // Consultar y marcar dentro de esta MISMA transacción es lo que
        // garantiza que nunca se aplique dos veces: si la generación
        // falla, la marca `aplicado` también se revierte.
        final netoAntesDeDescuentosInventario = fila.importeBase + fila.bonoPropuesto;
        final resuelto =
            await _resolverDescuentosAplicables(empleadoId: fila.empleadoId, netoDisponible: netoAntesDeDescuentosInventario);

        // Cuotas programadas (Etapa 15, "Descuentos Programados al
        // Personal") — se resuelven DESPUÉS de Inventario, contra el
        // remanente del neto (nunca ambos pools contra el mismo neto de
        // forma independiente, ver `calcularTotalesRenglonNomina`).
        final netoDisponibleParaProgramados = netoAntesDeDescuentosInventario - resuelto.suma;
        final resueltoProgramados = await _resolverCuotasProgramadasAplicables(
          empleadoId: fila.empleadoId,
          netoDisponible: netoDisponibleParaProgramados,
          fechaCorte: periodo.fechaPago,
        );

        final renglon = await _insertarRenglon(
          nominaId: nomina.id,
          datos: fila,
          prestamo: 0,
          tiempoExtra: 0,
          bono: fila.bonoPropuesto,
          bonoModificadoManualmente: false,
          faltas: 0,
          otrosDescuentos: 0,
          descuentosInventario: resuelto.suma,
          descuentosInventarioPendienteRevision: resuelto.pendienteRevision,
          descuentosProgramados: resueltoProgramados.suma,
          descuentosProgramadosPendienteRevision: resueltoProgramados.pendienteRevision,
          observaciones: null,
        );

        await _aplicarDescuentosResueltos(ids: resuelto.ids, nominaEmpleadoId: renglon.id);
        await _descuentoProgramadoRepository.reservarCuotas(cuotaIds: resueltoProgramados.ids, nominaEmpleadoId: renglon.id);
        await _resolverAusenciasDePeriodo(nominaEmpleadoId: renglon.id, empleadoId: fila.empleadoId, nomina: nomina);
        // Después de reservar cuotas: un renglón en $0 ya debe cruzar a
        // `pagado` desde este momento (ver doc comment de la clase).
        await _pagoNominaRepository.sincronizarEstatusPago(nominaEmpleadoId: renglon.id, actorUsuarioId: actorUsuarioId);
      }

      await _registrarEventoInterno(
        nominaId: nomina.id,
        tipoEvento: 'generada',
        actorUsuarioId: actorUsuarioId,
        observacion: '${filas.length} empleado(s) incluidos.',
      );

      return nomina;
    });
  }

  @override
  Future<NominaEmpleadoData> guardarRenglon({
    required String nominaId,
    required FilaNominaGenerada datos,
    required int prestamo,
    required int tiempoExtra,
    required int bono,
    required bool bonoModificadoManualmente,
    required int faltas,
    required int otrosDescuentos,
    required String? observaciones,
  }) {
    return _db.transaction(() async {
      final existente = await obtenerEmpleadoPorNominaYEmpleado(nominaId: nominaId, empleadoId: datos.empleadoId);
      final nomina = (await obtenerPorId(nominaId))!;

      // Descuentos de Inventario (Etapa 15, hallazgo real reportado por
      // Marlon: un descuento nacido DESPUÉS de generar el borrador
      // nunca entraba). Se recalculan en cada llamada — "Actualizar
      // desde Personal" ahora sí incorpora descuentos pendientes
      // nuevos, sin volver a aplicar los que ya estaban `aplicado` (la
      // consulta de pendientes nunca los vuelve a traer) y sin exceder
      // el neto disponible (lo ya aplicado antes también "ocupa" neto).
      final pagoPorDia = (datos.sueldoMensualUtilizado / 30).round();
      final descuentoPorFaltas = faltas * pagoPorDia;
      final yaAplicadoPrevio = existente?.descuentosInventario ?? 0;
      // Neto ANTES de resolver los descuentos de Inventario de esta
      // corrida (los ya aplicados se restan aparte, ver
      // `netoDisponible` abajo) — no usa `calcularTotalesRenglonNomina`
      // porque ese total final SÍ incluye `descuentosInventario`, que
      // todavía no se conoce en este punto (es lo que se está por
      // resolver).
      final netoAntesDeDescuentosInventario =
          datos.importeBase + bono + tiempoExtra - prestamo - descuentoPorFaltas - otrosDescuentos;
      final resuelto = await _resolverDescuentosAplicables(
        empleadoId: datos.empleadoId,
        netoDisponible: netoAntesDeDescuentosInventario - yaAplicadoPrevio,
      );
      final descuentosInventarioTotal = yaAplicadoPrevio + resuelto.suma;

      // Cuotas programadas — mismo truco `yaReservadoPrevio` que
      // Inventario: las ya reservadas en este renglón (de una corrida
      // anterior de `guardarRenglon`) se conservan tal cual, nunca se
      // vuelven a "concursar" por el neto (podrían perder su lugar
      // frente a una cuota más nueva) — solo se resuelven cuotas
      // ADICIONALES contra lo que sobra.
      final yaReservadoPrevio = existente == null
          ? 0
          : (await _descuentoProgramadoRepository.listarCuotasReservadasPorRenglon(existente.id))
              .fold<int>(0, (s, c) => s + c.importeProgramado);
      final netoDisponibleParaProgramados = netoAntesDeDescuentosInventario - descuentosInventarioTotal - yaReservadoPrevio;
      final resueltoProgramados = await _resolverCuotasProgramadasAplicables(
        empleadoId: datos.empleadoId,
        netoDisponible: netoDisponibleParaProgramados,
        fechaCorte: nomina.fechaPagoOrdinaria,
      );
      final descuentosProgramadosTotal = yaReservadoPrevio + resueltoProgramados.suma;

      // Nunca se borra+recrea el renglón: la FK `restrict` de
      // `DescuentoInventario.nominaEmpleadoId`/`DescuentoProgramadoCuota.
      // nominaEmpleadoId` rechazaría el `DELETE` en cuanto ese Empleado
      // tuviera cualquier descuento ya aplicado/reservado — y
      // "Actualizar desde Personal" debe poder correr repetidamente sin
      // romperse solo por eso. Ver `_actualizarRenglonExistente`.
      final renglon = existente != null
          ? await _actualizarRenglonExistente(
              existente: existente,
              datos: datos,
              prestamo: prestamo,
              tiempoExtra: tiempoExtra,
              bono: bono,
              bonoModificadoManualmente: bonoModificadoManualmente,
              faltas: faltas,
              otrosDescuentos: otrosDescuentos,
              descuentosInventario: descuentosInventarioTotal,
              descuentosInventarioPendienteRevision: resuelto.pendienteRevision,
              descuentosProgramados: descuentosProgramadosTotal,
              descuentosProgramadosPendienteRevision: resueltoProgramados.pendienteRevision,
              observaciones: observaciones,
            )
          : await _insertarRenglon(
              nominaId: nominaId,
              datos: datos,
              prestamo: prestamo,
              tiempoExtra: tiempoExtra,
              bono: bono,
              bonoModificadoManualmente: bonoModificadoManualmente,
              faltas: faltas,
              otrosDescuentos: otrosDescuentos,
              descuentosInventario: descuentosInventarioTotal,
              descuentosInventarioPendienteRevision: resuelto.pendienteRevision,
              descuentosProgramados: descuentosProgramadosTotal,
              descuentosProgramadosPendienteRevision: resueltoProgramados.pendienteRevision,
              observaciones: observaciones,
            );

      await _aplicarDescuentosResueltos(ids: resuelto.ids, nominaEmpleadoId: renglon.id);
      await _descuentoProgramadoRepository.reservarCuotas(cuotaIds: resueltoProgramados.ids, nominaEmpleadoId: renglon.id);
      await _resolverAusenciasDePeriodo(nominaEmpleadoId: renglon.id, empleadoId: datos.empleadoId, nomina: nomina);
      // Después de reservar cuotas: un renglón en $0 ya debe cruzar a
      // `pagado` desde este momento (ver doc comment de la clase).
      await _pagoNominaRepository.sincronizarEstatusPago(nominaEmpleadoId: renglon.id);
      return (await obtenerEmpleado(renglon.id))!;
    });
  }

  /// Ausencias (Etapa Tiempos Extra, pedido explícito de Marlon) —
  /// puramente informativas para "Ausencias del periodo", nunca tocan
  /// `faltas`/`descuentoPorFaltas`/ningún monto de este renglón. Mismo
  /// criterio exacto que `NominaEmpleadoTramo`: se borra y reinserta
  /// por completo en cada `guardarRenglon`.
  Future<void> _resolverAusenciasDePeriodo({
    required String nominaEmpleadoId,
    required String empleadoId,
    required NominaData nomina,
  }) async {
    await (_db.delete(_db.nominaEmpleadoAusencia)..where((t) => t.nominaEmpleadoId.equals(nominaEmpleadoId))).go();

    final ausencias = await _tiempoExtraRepository.listarAusenciasParaNomina(
      empleadoId: empleadoId,
      desde: nomina.fechaInicioPeriodo,
      hasta: nomina.fechaFinPeriodo,
    );
    for (final ausencia in ausencias) {
      await _db.into(_db.nominaEmpleadoAusencia).insert(
            NominaEmpleadoAusenciaCompanion.insert(
              nominaEmpleadoId: nominaEmpleadoId,
              tiempoExtraId: ausencia.tiempoExtraId,
              fecha: ausencia.fecha,
              motivoAusencia: ausencia.motivoAusencia,
              servicioId: Value(ausencia.servicioId),
              servicioNombre: ausencia.servicioNombre,
              nombreEmpleadoCubrio: ausencia.nombreCubre,
            ),
          );
    }
  }

  @override
  Future<void> eliminarRenglon(String nominaEmpleadoId, {String? motivo, String? actorUsuarioId}) {
    return _db.transaction(() async {
      final renglon = await (_db.select(_db.nominaEmpleado)..where((t) => t.id.equals(nominaEmpleadoId))).getSingle();

      // Chequeo defensivo propio (Etapa 5): el único llamador real hoy
      // (`ActualizarNominaDesdePersonalUseCase`, vía
      // `renglonNominaTieneMovimientosManuales`) ya filtra correctamente
      // antes de llegar aquí, pero este método no debe depender
      // exclusivamente de eso — un renglón con una
      // `DescuentoProgramadoCuota` todavía `reservada`/`aplicada`, o un
      // `DescuentoInventario` todavía `aplicado`, nunca debe borrarse en
      // silencio (la FK `restrict` de ambas tablas ya lo impediría a
      // nivel de SQLite, pero con un error genérico; esto falla con un
      // mensaje claro ANTES de tocar nada).
      final cuotasVivas = (await _descuentoProgramadoRepository.listarCuotasPorRenglon(nominaEmpleadoId))
          .where((c) => c.estatus == 'reservada' || c.estatus == 'aplicada');
      if (cuotasVivas.isNotEmpty) {
        throw StateError(
          'eliminarRenglon: el renglón $nominaEmpleadoId todavía tiene ${cuotasVivas.length} '
          'cuota(s) de Descuento Programado reservada(s)/aplicada(s) — libérela(s) primero.',
        );
      }
      final descuentosInventarioVivos = (await _asignacionRepository.listarDescuentosPorNominaEmpleado(nominaEmpleadoId))
          .where((d) => d.estatus == 'aplicado');
      if (descuentosInventarioVivos.isNotEmpty) {
        throw StateError(
          'eliminarRenglon: el renglón $nominaEmpleadoId todavía tiene ${descuentosInventarioVivos.length} '
          'DescuentoInventario aplicado(s) — revíertalo(s) primero.',
        );
      }

      // Etapa 4: sin esto, el `cascade` de `NominaEvento.nominaEmpleadoId`
      // destruiría cualquier evento previo de este renglón (ej. una
      // corrección anterior) junto con la fila — se desvincula
      // (nunca se borra) para que sobreviva en el timeline de la
      // Nómina completa.
      await (_db.update(_db.nominaEvento)..where((t) => t.nominaEmpleadoId.equals(nominaEmpleadoId)))
          .write(const NominaEventoCompanion(nominaEmpleadoId: Value(null)));

      await _registrarEventoInterno(
        nominaId: renglon.nominaId,
        tipoEvento: 'renglonEliminado',
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
        estadoAnterior: jsonEncode({
          'numeroEmpleado': renglon.numeroEmpleado,
          'nombreCompleto': renglon.nombreCompleto,
          'totalAPagar': renglon.totalAPagar,
          'estatusPago': renglon.estatusPago,
        }),
      );

      await (_db.delete(_db.nominaEmpleadoTramo)..where((t) => t.nominaEmpleadoId.equals(nominaEmpleadoId))).go();
      await (_db.delete(_db.nominaEmpleado)..where((t) => t.id.equals(nominaEmpleadoId))).go();
    });
  }

  @override
  Future<NominaEmpleadoData> actualizarRenglon({
    required String nominaEmpleadoId,
    required int prestamo,
    required int tiempoExtra,
    required int bono,
    required bool bonoModificadoManualmente,
    required int faltas,
    required int otrosDescuentos,
    required String? observaciones,
    ({int montoFiscal, int montoNoFiscal})? distribucionManual,
    required String tipoEvento,
    String? motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final actual = await obtenerEmpleado(nominaEmpleadoId);
      if (actual == null) {
        throw StateError('actualizarRenglon: NominaEmpleado $nominaEmpleadoId no existe.');
      }
      // `descuentosInventario`/`descuentosProgramados` nunca se editan
      // aquí — solo `generar()`/`guardarRenglon` los pueblan — pero sí
      // deben seguir restándose al recalcular.
      final totales = calcularTotalesRenglonNomina(
        importeBase: actual.importeBase,
        pagoPorDia: actual.pagoPorDia,
        bono: bono,
        tiempoExtra: tiempoExtra,
        prestamo: prestamo,
        faltas: faltas,
        otrosDescuentos: otrosDescuentos,
        descuentosInventario: actual.descuentosInventario,
        descuentosProgramados: actual.descuentosProgramados,
      );

      // Movimientos y distribución en UNA sola escritura transaccional
      // (Etapa 15, calculadora auditable — antes eran dos operaciones
      // separadas, "Guardar movimientos" y "Guardar distribución"): si
      // el usuario también tocó Fiscal/No fiscal, se valida y persiste
      // contra ESTE MISMO total recién calculado, nunca contra uno
      // parcial o desactualizado. Si no la tocó, se preserva el
      // comportamiento automático de siempre (`_resolverDistribucionFiscal`
      // — bug real Etapa 15: nunca dejar Fiscal/No fiscal congelados
      // ante un cambio de neto).
      final int montoFiscal;
      final int montoNoFiscal;
      final bool distribucionModificadaManualmente;
      final bool distribucionPendienteRevision;
      if (distribucionManual != null) {
        montoFiscal = distribucionManual.montoFiscal;
        montoNoFiscal = distribucionManual.montoNoFiscal;
        distribucionModificadaManualmente = true;
        distribucionPendienteRevision = false;
      } else {
        final distribucion = _resolverDistribucionFiscal(
          totalAPagar: totales.totalAPagar,
          distribucionModificadaManualmente: actual.distribucionModificadaManualmente,
          montoFiscalPrevio: actual.montoFiscal,
          montoNoFiscalPrevio: actual.montoNoFiscal,
        );
        montoFiscal = distribucion.montoFiscal;
        montoNoFiscal = distribucion.montoNoFiscal;
        distribucionModificadaManualmente = actual.distribucionModificadaManualmente;
        distribucionPendienteRevision = distribucion.pendienteRevision;
      }

      await (_db.update(_db.nominaEmpleado)..where((t) => t.id.equals(nominaEmpleadoId))).write(
        NominaEmpleadoCompanion(
          prestamo: Value(prestamo),
          tiempoExtra: Value(tiempoExtra),
          bono: Value(bono),
          bonoModificadoManualmente: Value(bonoModificadoManualmente),
          faltas: Value(faltas),
          descuentoPorFaltas: Value(totales.descuentoPorFaltas),
          otrosDescuentos: Value(otrosDescuentos),
          observaciones: Value(observaciones),
          montoFiscal: Value(montoFiscal),
          montoNoFiscal: Value(montoNoFiscal),
          distribucionModificadaManualmente: Value(distribucionModificadaManualmente),
          distribucionPendienteRevision: Value(distribucionPendienteRevision),
          totalAPagar: Value(totales.totalAPagar),
          updatedAt: Value(DateTime.now()),
        ),
      );
      // El neto pudo haber cambiado a/desde $0 (ver doc comment de la
      // clase) — sincronizar antes de devolver el renglón actualizado.
      await _pagoNominaRepository.sincronizarEstatusPago(nominaEmpleadoId: nominaEmpleadoId, actorUsuarioId: actorUsuarioId);

      // Etapa 4: escrito DENTRO de esta misma transacción (nunca una
      // segunda llamada después de que ya hizo commit) — solo si algo
      // realmente cambió.
      final diff = DiffEvento()
        ..anotar('prestamo', actual.prestamo, prestamo)
        ..anotar('tiempoExtra', actual.tiempoExtra, tiempoExtra)
        ..anotar('bono', actual.bono, bono)
        ..anotar('faltas', actual.faltas, faltas)
        ..anotar('otrosDescuentos', actual.otrosDescuentos, otrosDescuentos)
        ..anotar('observaciones', actual.observaciones, observaciones)
        ..anotar('montoFiscal', actual.montoFiscal, montoFiscal)
        ..anotar('montoNoFiscal', actual.montoNoFiscal, montoNoFiscal)
        ..anotar('totalAPagar', actual.totalAPagar, totales.totalAPagar);
      if (diff.hayCambios) {
        await _registrarEventoInterno(
          nominaId: actual.nominaId,
          nominaEmpleadoId: nominaEmpleadoId,
          tipoEvento: tipoEvento,
          observacion: motivo,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          actorUsuarioId: actorUsuarioId,
        );
      }

      return (await obtenerEmpleado(nominaEmpleadoId))!;
    });
  }

  @override
  Future<NominaData> cerrar({required String nominaId, String? actorUsuarioId}) {
    return _db.transaction(() async {
      await (_db.update(_db.nomina)..where((t) => t.id.equals(nominaId))).write(
        NominaCompanion(
          estatus: const Value('cerrada'),
          fechaCierre: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _registrarEventoInterno(nominaId: nominaId, tipoEvento: 'cerrada', actorUsuarioId: actorUsuarioId);
      return (await obtenerPorId(nominaId))!;
    });
  }

  @override
  Future<NominaData> cancelar({
    required String nominaId,
    required String motivo,
    String? detalle,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final renglones = await listarEmpleados(nominaId);
      final renglonIds = [for (final r in renglones) r.id];

      // Mismo mecanismo exacto que `eliminarFisicamente`, con una
      // salvedad: un renglón en $0 SÍ puede llegar a `aplicada` sin
      // ningún `PagoNomina` real (ver `sincronizarEstatusPago` y
      // `nomina_estatus_pago_cero_test.dart`) — `liberarCuotasDeRenglones`
      // ya trata `reservada`/`aplicada` de forma uniforme, así que esto
      // libera correctamente ambos casos sin distinguirlos.
      await _asignacionRepository.revertirDescuentosAplicados(renglonIds);
      await _descuentoProgramadoRepository.liberarCuotasDeRenglones(
        renglonIds,
        observacion: 'Liberada: la Nómina fue cancelada. Motivo: $motivo',
        actorUsuarioId: actorUsuarioId,
      );

      await (_db.update(_db.nomina)..where((t) => t.id.equals(nominaId))).write(
        NominaCompanion(
          estatus: const Value('cancelada'),
          motivoCancelacionCodigo: Value(motivo),
          motivoCancelacionDetalle: Value(detalle),
          motivoCancelacionObservaciones: Value(observaciones),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _registrarEventoInterno(
        nominaId: nominaId,
        tipoEvento: 'cancelada',
        observacion: observaciones ?? detalle ?? motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return (await obtenerPorId(nominaId))!;
    });
  }

  Future<void> _registrarEventoInterno({
    required String nominaId,
    String? nominaEmpleadoId,
    required String tipoEvento,
    String? observacion,
    String? estadoAnterior,
    String? estadoNuevo,
    String? actorUsuarioId,
  }) {
    return _db.into(_db.nominaEvento).insert(
          NominaEventoCompanion.insert(
            nominaId: nominaId,
            nominaEmpleadoId: Value(nominaEmpleadoId),
            fechaHora: DateTime.now(),
            tipoEvento: tipoEvento,
            observacion: Value(observacion),
            estadoAnterior: Value(estadoAnterior),
            estadoNuevo: Value(estadoNuevo),
            actorUsuarioId: Value(actorUsuarioId),
          ),
        );
  }

  @override
  Future<void> registrarEvento({
    required String nominaId,
    String? nominaEmpleadoId,
    required String tipoEvento,
    String? observacion,
    String? estadoAnterior,
    String? estadoNuevo,
    String? actorUsuarioId,
  }) {
    return _registrarEventoInterno(
      nominaId: nominaId,
      nominaEmpleadoId: nominaEmpleadoId,
      tipoEvento: tipoEvento,
      observacion: observacion,
      estadoAnterior: estadoAnterior,
      estadoNuevo: estadoNuevo,
      actorUsuarioId: actorUsuarioId,
    );
  }

  /// Único bloqueo real (Etapa 15): la Nómina ya no está en Borrador
  /// (Cerrada/Pagada — "el cálculo quedó aprobado", ver el doc comment
  /// de `CerrarNominaUseCase`), o ya tiene un `PagoNomina` real
  /// registrado — dinero que efectivamente salió, nunca se toca. Un
  /// Borrador estructuralmente nunca puede tener `PagoNomina`
  /// (`RegistrarPagoNominaUseCase` exige `estatus == cerrada`), así que
  /// este segundo chequeo es defensivo, no la ruta esperada.
  @override
  Future<ResumenEliminacionNomina> obtenerResumenEliminacionFisica(String nominaId) async {
    final nomina = await obtenerPorId(nominaId);
    if (nomina == null) return const ResumenEliminacionNomina(existe: false);

    if (nomina.estatus != 'borrador') {
      return ResumenEliminacionNomina(
        existe: true,
        detalleBloqueo: 'Esta Nómina ya está "${nomina.estatus}" — solo una Nómina en Borrador puede eliminarse físicamente.',
      );
    }

    final pagos = await (_db.select(_db.pagoNomina)..where((t) => t.nominaId.equals(nominaId))).get();
    if (pagos.isNotEmpty) {
      return const ResumenEliminacionNomina(
        existe: true,
        detalleBloqueo: 'Esta Nómina ya tiene pagos registrados — no puede eliminarse.',
      );
    }

    return const ResumenEliminacionNomina(existe: true);
  }

  /// Eliminación física extraordinaria (Etapa 15) — Maestro-only. Solo
  /// aplica sobre un Borrador sin `PagoNomina` (ver
  /// [obtenerResumenEliminacionFisica]). Antes de borrar, revierte a
  /// `pendiente` cualquier `DescuentoInventario` que esta Nómina haya
  /// aplicado — la deuda del Empleado nunca debe desaparecer solo
  /// porque se borró el intento de Nómina que la había consumido.
  /// `NominaEmpleado`/`NominaEmpleadoTramo`/`NominaEvento` se limpian
  /// solos vía `cascade` al borrar la fila de `Nomina`.
  @override
  Future<EliminarNominaFisicamenteResultado> eliminarFisicamente({
    required String nominaId,
    required String motivo,
    String? detalle,
    String? actorUsuarioId,
  }) async {
    final etiquetaMotivo =
        MotivoEliminacionFisicaNomina.values.where((m) => m.name == motivo).firstOrNull?.etiqueta ?? motivo;

    final nominaInicial = await obtenerPorId(nominaId);
    if (nominaInicial == null) return EliminarNominaFisicamenteNoExiste();

    final resumen = await obtenerResumenEliminacionFisica(nominaId);
    if (resumen.bloqueado) {
      return EliminarNominaFisicamenteTieneDependencias(resumen.detalleBloqueo!);
    }

    final renglones = await listarEmpleados(nominaId);

    await _db.transaction(() async {
      final tramosPorRenglon = <String, List<NominaEmpleadoTramoData>>{};
      for (final renglon in renglones) {
        tramosPorRenglon[renglon.id] = await listarTramos(renglon.id);
      }
      // Etapa 4 (hallazgo real de auditoría): `NominaEvento` es
      // `cascade` desde `Nomina`/`NominaEmpleado` — sin capturarlo
      // aquí ANTES del `DELETE`, todo el historial de esta Nómina
      // (incluida su propia auditoría de generación) desaparecería sin
      // dejar ningún rastro, ni siquiera en este snapshot.
      final eventos = await listarEventos(nominaId);

      final snapshot = <String, Object?>{
        'nomina': nominaInicial.toJson(),
        'renglones': [for (final r in renglones) r.toJson()],
        'tramosPorRenglon': {for (final e in tramosPorRenglon.entries) e.key: [for (final t in e.value) t.toJson()]},
        'eventos': [for (final e in eventos) e.toJson()],
      };

      // Descuentos de Inventario aplicados por esta Nómina — vuelven a
      // `pendiente`, nunca desaparecen (Resolución explícita de Marlon).
      await _asignacionRepository.revertirDescuentosAplicados([for (final r in renglones) r.id]);
      // Cuotas de Descuentos Programados (Etapa 15) reservadas por esta
      // Nómina — un Borrador solo puede tenerlas `reservada` (nunca
      // `aplicada`, eso exige un pago real), así que esto siempre las
      // libera sin tocar ningún `saldoPendiente`.
      await _descuentoProgramadoRepository.liberarCuotasDeRenglones(
        [for (final r in renglones) r.id],
        observacion: 'Liberada: la Nómina ${nominaInicial.folio} (Borrador) fue eliminada físicamente.',
        actorUsuarioId: actorUsuarioId,
      );

      await _db.into(_db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'nomina',
              entidadIdOriginal: nominaId,
              fechaHora: DateTime.now(),
              motivo: etiquetaMotivo,
              motivoCodigo: Value(motivo),
              detalle: Value(detalle),
              snapshotJson: jsonEncode(snapshot),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );

      // `NominaEmpleado`/`NominaEmpleadoTramo`/`NominaEvento` son
      // `cascade` desde `Nomina` — se limpian solos. La FK `restrict`
      // de `DescuentoInventario.nominaEmpleadoId` ya no bloquea nada
      // porque se revirtió arriba.
      await (_db.delete(_db.nomina)..where((t) => t.id.equals(nominaId))).go();
    });

    return EliminarNominaFisicamenteExitoso();
  }

  /// "Eliminar cadena de prueba" (Etapa 15, ampliación de la limpieza
  /// segura de datos de prueba — mismo concepto ya construido para
  /// Compra) — a diferencia de [eliminarFisicamente] (bloquea ante
  /// CUALQUIER Nómina que no sea Borrador o que ya tenga un
  /// `PagoNomina`), esta acción SÍ alcanza una Nómina `cerrada`/
  /// `pagada` junto con TODOS sus `PagoNomina` (una Nómina puede tener
  /// varios, ver el doc comment de `PagoNomina`) y el `Egreso` de cada
  /// uno — pero únicamente por relación de IDs exacta y solo cuando
  /// nada cruzó un punto irreversible real.
  ///
  /// **Puntos irreversibles investigados para este dominio** (Etapa
  /// 15, antes de implementar — reportados a Marlon):
  /// 1. Este proyecto no tiene ningún concepto de CFDI/timbrado/
  ///    complemento fiscal para Nómina ni para su Egreso —
  ///    `ComplementoPago` (el único CFDI del proyecto) referencia
  ///    exclusivamente `Pago` (ingresos/CxC), nunca `PagoNomina`. No
  ///    existe ningún riesgo fiscal real que bloquear aquí.
  /// 2. `Egreso` no guarda su propio origen (se infiere por relación
  ///    inversa) y la exclusividad 1:1 `PagoNomina.egresoId`↔`Compra.egresoId`
  ///    es una invariante de aplicación, no una constraint de esquema
  ///    cruzada — así que SÍ se verifica aquí explícitamente que
  ///    ningún `Compra.egresoId` apunte al mismo Egreso antes de darlo
  ///    por "propio" de este `PagoNomina` (mismo criterio que
  ///    `EgresoRepositoryImpl.obtenerResumenEliminacionFisica`).
  /// 3. `DescuentoInventario` aplicado por esta Nómina NUNCA bloquea —
  ///    se revierte a `pendiente` (nunca se elimina), igual que
  ///    [eliminarFisicamente]: es la política explícita de Marlon para
  ///    esta ampliación ("el descuento representa una deuda/incidencia
  ///    de Inventario, no de Nómina").
  @override
  Future<ResumenCadenaPruebaNomina> obtenerResumenCadenaPrueba(String nominaId) async {
    final nomina = await obtenerPorId(nominaId);
    if (nomina == null) return const ResumenCadenaPruebaNomina(existe: false);

    final renglones = await listarEmpleados(nominaId);
    final totalAPagar = renglones.fold<int>(0, (s, r) => s + r.totalAPagar);

    final pagos = await (_db.select(_db.pagoNomina)..where((t) => t.nominaId.equals(nominaId))).get();

    final pagosPreview = <PagoEnCadenaPruebaNomina>[];
    for (final pago in pagos) {
      String? folioEgreso;
      final egresoId = pago.egresoId;
      if (egresoId != null) {
        // Punto irreversible: el Egreso de este pago resulta
        // referenciado también por una Compra — la exclusividad 1:1 es
        // solo una invariante de aplicación, nunca una constraint de
        // esquema cruzada, así que se verifica explícitamente.
        final compraAmbigua = await (_db.select(_db.compra)..where((t) => t.egresoId.equals(egresoId))).getSingleOrNull();
        if (compraAmbigua != null) {
          return ResumenCadenaPruebaNomina(
            existe: true,
            folioNomina: nomina.folio,
            estatus: nomina.estatus,
            detalleBloqueo:
                'El Egreso del pago ${pago.folioPagoNomina} también está referenciado por la Compra '
                '${compraAmbigua.folioCompra} — no se puede atribuir con exactitud, así que no puede limpiarse '
                'como cadena de prueba.',
          );
        }
        final egreso = await (_db.select(_db.egreso)..where((t) => t.id.equals(egresoId))).getSingleOrNull();
        folioEgreso = egreso?.folioEgreso;
      }
      pagosPreview.add(PagoEnCadenaPruebaNomina(folioPagoNomina: pago.folioPagoNomina, montoTotal: pago.montoTotal, folioEgreso: folioEgreso));
    }

    var descuentosAplicados = 0;
    var totalDescuentosAplicados = 0;
    for (final renglon in renglones) {
      final descuentos = await (_db.select(_db.descuentoInventario)..where((t) => t.nominaEmpleadoId.equals(renglon.id))).get();
      for (final d in descuentos) {
        if (d.estatus == 'aplicado') {
          descuentosAplicados++;
          totalDescuentosAplicados += d.importe;
        }
      }
    }

    return ResumenCadenaPruebaNomina(
      existe: true,
      folioNomina: nomina.folio,
      estatus: nomina.estatus,
      totalEmpleados: renglones.length,
      totalAPagar: totalAPagar,
      pagos: pagosPreview,
      descuentosInventarioAplicados: descuentosAplicados,
      totalDescuentosInventarioAplicados: totalDescuentosAplicados,
    );
  }

  @override
  Future<EliminarCadenaPruebaNominaResultado> eliminarCadenaPrueba({
    required String nominaId,
    required String motivo,
    String? detalle,
    String? actorUsuarioId,
  }) async {
    final etiquetaMotivo = MotivoCadenaPruebaNomina.values.where((m) => m.name == motivo).firstOrNull?.etiqueta ?? motivo;

    final nominaInicial = await obtenerPorId(nominaId);
    if (nominaInicial == null) return EliminarCadenaPruebaNominaNoExiste();

    final resumen = await obtenerResumenCadenaPrueba(nominaId);
    if (resumen.bloqueado) {
      return EliminarCadenaPruebaNominaTieneDependencias(resumen.detalleBloqueo!);
    }

    final renglones = await listarEmpleados(nominaId);
    final renglonIds = [for (final r in renglones) r.id];
    final pagos = await (_db.select(_db.pagoNomina)..where((t) => t.nominaId.equals(nominaId))).get();

    await _db.transaction(() async {
      final tramosPorRenglon = <String, List<NominaEmpleadoTramoData>>{};
      for (final renglon in renglones) {
        tramosPorRenglon[renglon.id] = await listarTramos(renglon.id);
      }

      final aplicacionesPorPago = <String, List<AplicacionPagoNominaData>>{};
      final egresosPorPago = <String, EgresoData?>{};
      final eventosPorPago = <String, List<PagoNominaEventoData>>{};
      for (final pago in pagos) {
        aplicacionesPorPago[pago.id] =
            await (_db.select(_db.aplicacionPagoNomina)..where((t) => t.pagoNominaId.equals(pago.id))).get();
        egresosPorPago[pago.id] =
            pago.egresoId == null ? null : await (_db.select(_db.egreso)..where((t) => t.id.equals(pago.egresoId!))).getSingleOrNull();
        // Etapa 4 (hallazgo real de auditoría): `PagoNominaEvento` es
        // `cascade` desde `PagoNomina` — sin capturarlo aquí, se
        // pierde el historial completo de un pago REAL (registrado/
        // corregido/cancelado/comprobante) que esta acción puede
        // borrar junto con una Nómina `cerrada`/`pagada`.
        eventosPorPago[pago.id] = await (_db.select(_db.pagoNominaEvento)..where((t) => t.pagoNominaId.equals(pago.id))).get();
      }

      // Etapa 4: mismo motivo que `eliminarFisicamente` — el propio
      // historial de la Nómina también es `cascade`.
      final eventos = await listarEventos(nominaId);

      final snapshot = <String, Object?>{
        'nomina': nominaInicial.toJson(),
        'renglones': [for (final r in renglones) r.toJson()],
        'tramosPorRenglon': {for (final e in tramosPorRenglon.entries) e.key: [for (final t in e.value) t.toJson()]},
        'pagos': [for (final p in pagos) p.toJson()],
        'aplicacionesPorPago': {for (final e in aplicacionesPorPago.entries) e.key: [for (final a in e.value) a.toJson()]},
        'egresosPorPago': {for (final e in egresosPorPago.entries) e.key: e.value?.toJson()},
        'eventosPorPago': {for (final e in eventosPorPago.entries) e.key: [for (final ev in e.value) ev.toJson()]},
        'eventos': [for (final e in eventos) e.toJson()],
      };

      // Descuentos de Inventario aplicados por esta Nómina — vuelven a
      // `pendiente`, nunca desaparecen (misma política que
      // [eliminarFisicamente] y resolución explícita de Marlon para
      // esta ampliación: representan una deuda/incidencia de
      // Inventario, no de Nómina).
      await _asignacionRepository.revertirDescuentosAplicados(renglonIds);
      // Cuotas de Descuentos Programados (Etapa 15) — el caso crítico:
      // si la Nómina estaba `pagada`, estas cuotas están `aplicada` con
      // `saldoPendiente` ya decrecido; `liberarCuotasDeRenglones` lo
      // detecta y lo restaura (des-liquidando el padre si corresponde)
      // dentro de esta MISMA transacción, antes de que la fila de
      // Nómina desaparezca. Si estaba `cerrada` sin pagar, las cuotas
      // siguen `reservada` — se liberan igual, sin tocar saldo.
      await _descuentoProgramadoRepository.liberarCuotasDeRenglones(
        renglonIds,
        observacion: 'Revertida: la Nómina ${nominaInicial.folio} fue eliminada como cadena de prueba.',
        actorUsuarioId: actorUsuarioId,
      );

      // `AplicacionPagoNomina` es `restrict` hacia `PagoNomina` y
      // `NominaEmpleado` — se borra primero (nunca se "revierte" el
      // `estatusPago` del renglón porque el renglón completo
      // desaparece en este mismo paso).
      for (final pago in pagos) {
        await (_db.delete(_db.aplicacionPagoNomina)..where((t) => t.pagoNominaId.equals(pago.id))).go();

        // Comprobantes del pago — `PagoNominaAttachment` es `cascade`
        // sobre `PagoNomina`, pero el `Attachment` en sí queda
        // huérfano si no se borra explícitamente.
        final adjuntosPagoQuery = _db.select(_db.attachment).join([
          innerJoin(_db.pagoNominaAttachment, _db.pagoNominaAttachment.attachmentId.equalsExp(_db.attachment.id)),
        ])
          ..where(_db.pagoNominaAttachment.pagoNominaId.equals(pago.id));
        final adjuntosPago = await adjuntosPagoQuery.map((row) => row.readTable(_db.attachment)).get();
        for (final adjunto in adjuntosPago) {
          await (_db.delete(_db.attachment)..where((t) => t.id.equals(adjunto.id))).go();
        }
      }

      // `PagoNominaEvento` es `cascade` sobre `PagoNomina` — se limpia
      // solo.
      for (final pago in pagos) {
        await (_db.delete(_db.pagoNomina)..where((t) => t.id.equals(pago.id))).go();
      }

      // El Egreso de cada pago — DESPUÉS de borrar el `PagoNomina`
      // (`PagoNomina.egresoId` es `restrict` hacia `Egreso`).
      for (final entry in egresosPorPago.entries) {
        final egreso = entry.value;
        if (egreso == null) continue;
        final adjuntosEgresoQuery = _db.select(_db.attachment).join([
          innerJoin(_db.egresoAttachment, _db.egresoAttachment.attachmentId.equalsExp(_db.attachment.id)),
        ])
          ..where(_db.egresoAttachment.egresoId.equals(egreso.id));
        final adjuntosEgreso = await adjuntosEgresoQuery.map((row) => row.readTable(_db.attachment)).get();
        for (final adjunto in adjuntosEgreso) {
          await (_db.delete(_db.attachment)..where((t) => t.id.equals(adjunto.id))).go();
        }
        await (_db.delete(_db.egreso)..where((t) => t.id.equals(egreso.id))).go();
      }

      await _db.into(_db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'nomina',
              entidadIdOriginal: nominaId,
              fechaHora: DateTime.now(),
              motivo: etiquetaMotivo,
              motivoCodigo: Value(motivo),
              detalle: Value(detalle),
              snapshotJson: jsonEncode(snapshot),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );

      // `NominaEmpleado`/`NominaEmpleadoTramo`/`NominaEvento` son
      // `cascade` desde `Nomina` — se limpian solos. Las FK `restrict`
      // de `DescuentoInventario.nominaEmpleadoId` y `PagoNomina.nominaId`
      // ya no bloquean nada: se revirtió/borró todo arriba.
      await (_db.delete(_db.nomina)..where((t) => t.id.equals(nominaId))).go();
    });

    return EliminarCadenaPruebaNominaExitoso();
  }
}
