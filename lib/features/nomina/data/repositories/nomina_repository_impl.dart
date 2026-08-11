import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/nomina_repository.dart';
import '../../domain/usecases/calcular_periodo_nomina.dart';
import '../../domain/usecases/fila_nomina_generada.dart';
import '../tables/nomina_table.dart' show TipoPeriodoNomina;

class NominaRepositoryImpl implements NominaRepository {
  NominaRepositoryImpl(this._db);

  final AppDatabase _db;

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
  Future<List<NominaEventoData>> listarEventos(String nominaId) {
    return (_db.select(_db.nominaEvento)
          ..where((t) => t.nominaId.equals(nominaId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaHora)]))
        .get();
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
    required String? observaciones,
    required int montoFiscal,
    required int montoNoFiscal,
    required bool distribucionModificadaManualmente,
    required bool distribucionPendienteRevision,
  }) async {
    final pagoPorDia = (datos.sueldoMensualUtilizado / 30).round();
    final descuentoPorFaltas = faltas * pagoPorDia;
    final totalAPagar =
        datos.importeBase + bono + tiempoExtra - prestamo - descuentoPorFaltas - otrosDescuentos;

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
            observaciones: Value(observaciones),
            montoFiscal: Value(montoFiscal),
            montoNoFiscal: Value(montoNoFiscal),
            distribucionModificadaManualmente: Value(distribucionModificadaManualmente),
            distribucionPendienteRevision: Value(distribucionPendienteRevision),
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
        await _insertarRenglon(
          nominaId: nomina.id,
          datos: fila,
          prestamo: 0,
          tiempoExtra: 0,
          bono: fila.bonoPropuesto,
          bonoModificadoManualmente: false,
          faltas: 0,
          otrosDescuentos: 0,
          observaciones: null,
          montoFiscal: fila.importeBase + fila.bonoPropuesto,
          montoNoFiscal: 0,
          distribucionModificadaManualmente: false,
          distribucionPendienteRevision: false,
        );
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
    required int montoFiscal,
    required int montoNoFiscal,
    required bool distribucionModificadaManualmente,
    required bool distribucionPendienteRevision,
  }) {
    return _db.transaction(() async {
      final existente = await obtenerEmpleadoPorNominaYEmpleado(nominaId: nominaId, empleadoId: datos.empleadoId);
      if (existente != null) {
        await (_db.delete(_db.nominaEmpleadoTramo)..where((t) => t.nominaEmpleadoId.equals(existente.id))).go();
        await (_db.delete(_db.nominaEmpleado)..where((t) => t.id.equals(existente.id))).go();
      }
      return _insertarRenglon(
        nominaId: nominaId,
        datos: datos,
        prestamo: prestamo,
        tiempoExtra: tiempoExtra,
        bono: bono,
        bonoModificadoManualmente: bonoModificadoManualmente,
        faltas: faltas,
        otrosDescuentos: otrosDescuentos,
        observaciones: observaciones,
        montoFiscal: montoFiscal,
        montoNoFiscal: montoNoFiscal,
        distribucionModificadaManualmente: distribucionModificadaManualmente,
        distribucionPendienteRevision: distribucionPendienteRevision,
      );
    });
  }

  @override
  Future<void> eliminarRenglon(String nominaEmpleadoId) {
    return _db.transaction(() async {
      await (_db.delete(_db.nominaEmpleadoTramo)..where((t) => t.nominaEmpleadoId.equals(nominaEmpleadoId))).go();
      await (_db.delete(_db.nominaEmpleado)..where((t) => t.id.equals(nominaEmpleadoId))).go();
    });
  }

  @override
  Future<NominaEmpleadoData> actualizarMovimientos({
    required String nominaEmpleadoId,
    required int prestamo,
    required int tiempoExtra,
    required int bono,
    required bool bonoModificadoManualmente,
    required int faltas,
    required int otrosDescuentos,
    required String? observaciones,
  }) async {
    final actual = await obtenerEmpleado(nominaEmpleadoId);
    if (actual == null) {
      throw StateError('actualizarMovimientos: NominaEmpleado $nominaEmpleadoId no existe.');
    }
    final descuentoPorFaltas = faltas * actual.pagoPorDia;
    final totalAPagar = actual.importeBase + bono + tiempoExtra - prestamo - descuentoPorFaltas - otrosDescuentos;

    await (_db.update(_db.nominaEmpleado)..where((t) => t.id.equals(nominaEmpleadoId))).write(
      NominaEmpleadoCompanion(
        prestamo: Value(prestamo),
        tiempoExtra: Value(tiempoExtra),
        bono: Value(bono),
        bonoModificadoManualmente: Value(bonoModificadoManualmente),
        faltas: Value(faltas),
        descuentoPorFaltas: Value(descuentoPorFaltas),
        otrosDescuentos: Value(otrosDescuentos),
        observaciones: Value(observaciones),
        totalAPagar: Value(totalAPagar),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (await obtenerEmpleado(nominaEmpleadoId))!;
  }

  @override
  Future<NominaEmpleadoData> actualizarDistribucion({
    required String nominaEmpleadoId,
    required int montoFiscal,
    required int montoNoFiscal,
  }) async {
    await (_db.update(_db.nominaEmpleado)..where((t) => t.id.equals(nominaEmpleadoId))).write(
      NominaEmpleadoCompanion(
        montoFiscal: Value(montoFiscal),
        montoNoFiscal: Value(montoNoFiscal),
        distribucionModificadaManualmente: const Value(true),
        distribucionPendienteRevision: const Value(false),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (await obtenerEmpleado(nominaEmpleadoId))!;
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

  Future<void> _registrarEventoInterno({
    required String nominaId,
    String? nominaEmpleadoId,
    required String tipoEvento,
    String? observacion,
    String? actorUsuarioId,
  }) {
    return _db.into(_db.nominaEvento).insert(
          NominaEventoCompanion.insert(
            nominaId: nominaId,
            nominaEmpleadoId: Value(nominaEmpleadoId),
            fechaHora: DateTime.now(),
            tipoEvento: tipoEvento,
            observacion: Value(observacion),
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
    String? actorUsuarioId,
  }) {
    return _registrarEventoInterno(
      nominaId: nominaId,
      nominaEmpleadoId: nominaEmpleadoId,
      tipoEvento: tipoEvento,
      observacion: observacion,
      actorUsuarioId: actorUsuarioId,
    );
  }
}
