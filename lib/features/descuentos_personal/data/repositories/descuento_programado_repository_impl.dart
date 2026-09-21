import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/egreso_repository.dart';

import '../tables/descuento_programado_cuota_table.dart';
import '../../domain/repositories/descuento_programado_repository.dart';

class DescuentoProgramadoRepositoryImpl
    implements DescuentoProgramadoRepository {
  DescuentoProgramadoRepositoryImpl(
    this._db,
    this._egresoRepository,
    this._codigoSecuencia,
  );

  final AppDatabase _db;
  final EgresoRepository _egresoRepository;
  final CodigoSecuenciaService _codigoSecuencia;

  @override
  Future<DescuentoProgramadoEmpleadoData?> obtenerPorId(String id) {
    return (_db.select(_db.descuentoProgramadoEmpleado)
      ..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<DescuentoProgramadoEmpleadoData>> listarPorEmpleado(
    String empleadoId,
  ) {
    return (_db.select(_db.descuentoProgramadoEmpleado)
          ..where((t) => t.empleadoId.equals(empleadoId))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaRegistro)]))
        .get();
  }

  @override
  Future<List<DescuentoProgramadoEmpleadoData>> listarTodos() {
    return (_db.select(_db.descuentoProgramadoEmpleado)
      ..orderBy([(t) => OrderingTerm.desc(t.fechaRegistro)])).get();
  }

  @override
  Future<List<DescuentoProgramadoCuotaData>> listarCuotas(
    String descuentoProgramadoId,
  ) {
    return (_db.select(_db.descuentoProgramadoCuota)
          ..where((t) => t.descuentoProgramadoId.equals(descuentoProgramadoId))
          ..orderBy([(t) => OrderingTerm.asc(t.numeroCuota)]))
        .get();
  }

  @override
  Future<Map<String, int>> contarCuotasPorDescuento(Iterable<String> ids) async {
    final unicos = ids.toSet();
    if (unicos.isEmpty) return {};
    final conteo = _db.descuentoProgramadoCuota.id.count();
    final query = _db.selectOnly(_db.descuentoProgramadoCuota)
      ..addColumns([_db.descuentoProgramadoCuota.descuentoProgramadoId, conteo])
      ..where(_db.descuentoProgramadoCuota.descuentoProgramadoId.isIn(unicos) &
          _db.descuentoProgramadoCuota.estatus.equals(EstatusDescuentoProgramadoCuota.cancelada.name).not())
      ..groupBy([_db.descuentoProgramadoCuota.descuentoProgramadoId]);
    final filas = await query.get();
    return {
      for (final fila in filas)
        fila.read(_db.descuentoProgramadoCuota.descuentoProgramadoId)!: fila.read(conteo) ?? 0,
    };
  }

  @override
  Future<List<DescuentoProgramadoMovimientoData>> listarMovimientos(
    String descuentoProgramadoId,
  ) {
    return (_db.select(_db.descuentoProgramadoMovimiento)
          ..where((t) => t.descuentoProgramadoId.equals(descuentoProgramadoId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaHora)]))
        .get();
  }

  @override
  Future<DescuentoProgramadoEmpleadoData?> obtenerPorEgresoId(String egresoId) {
    return (_db.select(_db.descuentoProgramadoEmpleado)
      ..where((t) => t.egresoId.equals(egresoId))).getSingleOrNull();
  }

  @override
  Future<List<String>> listarEgresoIdsEnRango({DateTime? rangoInicio, DateTime? rangoFin}) async {
    final query = _db.select(_db.descuentoProgramadoEmpleado)..where((t) => t.egresoId.isNotNull());
    if (rangoInicio != null) query.where((t) => t.fechaRegistro.isBiggerOrEqualValue(rangoInicio));
    if (rangoFin != null) query.where((t) => t.fechaRegistro.isSmallerOrEqualValue(rangoFin));
    final descuentos = await query.get();
    return [for (final d in descuentos) d.egresoId!];
  }

  @override
  Future<List<DescuentoProgramadoCuotaData>> listarCuotasPendientesPorEmpleado(
    String empleadoId,
  ) {
    final query = _db.select(_db.descuentoProgramadoCuota).join([
      innerJoin(
        _db.descuentoProgramadoEmpleado,
        _db.descuentoProgramadoEmpleado.id.equalsExp(
          _db.descuentoProgramadoCuota.descuentoProgramadoId,
        ),
      ),
    ])..where(
      _db.descuentoProgramadoEmpleado.empleadoId.equals(empleadoId) &
          _db.descuentoProgramadoCuota.estatus.equals('pendiente'),
    );
    return query
        .map((row) => row.readTable(_db.descuentoProgramadoCuota))
        .get();
  }

  @override
  Future<List<DescuentoProgramadoCuotaData>> listarCuotasReservadasPorRenglon(
    String nominaEmpleadoId,
  ) {
    return (_db.select(_db.descuentoProgramadoCuota)..where(
      (t) =>
          t.nominaEmpleadoId.equals(nominaEmpleadoId) &
          t.estatus.equals('reservada'),
    )).get();
  }

  @override
  Future<List<DescuentoProgramadoCuotaData>> listarCuotasPorRenglon(
    String nominaEmpleadoId,
  ) {
    return (_db.select(_db.descuentoProgramadoCuota)
      ..where((t) => t.nominaEmpleadoId.equals(nominaEmpleadoId))).get();
  }

  Future<void> _registrarMovimiento({
    required String descuentoProgramadoId,
    String? cuotaId,
    required String tipoMovimiento,
    int? importe,
    String? observacion,
    String? actorUsuarioId,
    Map<String, dynamic>? datosRelevantes,
    String? estadoAnterior,
    String? estadoNuevo,
  }) {
    return _db
        .into(_db.descuentoProgramadoMovimiento)
        .insert(
          DescuentoProgramadoMovimientoCompanion.insert(
            descuentoProgramadoId: descuentoProgramadoId,
            cuotaId: Value(cuotaId),
            fechaHora: DateTime.now(),
            tipoMovimiento: tipoMovimiento,
            importe: Value(importe),
            observacion: Value(observacion),
            actorUsuarioId: Value(actorUsuarioId),
            datosRelevantes: Value(
              datosRelevantes == null ? null : jsonEncode(datosRelevantes),
            ),
            estadoAnterior: Value(estadoAnterior),
            estadoNuevo: Value(estadoNuevo),
          ),
        );
  }

  @override
  Future<DescuentoProgramadoEmpleadoData> registrar({
    required String folio,
    required String empleadoId,
    required String tipo,
    required DateTime fechaRegistro,
    required int importeOriginal,
    String? descripcion,
    String? asignacionOrigenId,
    String? observaciones,
    required List<({int numeroCuota, DateTime fechaProgramada, int importe})>
    cuotas,
    String? cuentaFinancieraId,
    String? beneficiarioEgreso,
    String? formaPagoEgreso,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      var descuento = await _db
          .into(_db.descuentoProgramadoEmpleado)
          .insertReturning(
            DescuentoProgramadoEmpleadoCompanion.insert(
              folio: folio,
              empleadoId: empleadoId,
              tipo: tipo,
              fechaRegistro: fechaRegistro,
              importeOriginal: importeOriginal,
              saldoPendiente: importeOriginal,
              descripcion: Value(descripcion),
              asignacionOrigenId: Value(asignacionOrigenId),
              observaciones: Value(observaciones),
            ),
          );

      for (final cuota in cuotas) {
        await _db
            .into(_db.descuentoProgramadoCuota)
            .insert(
              DescuentoProgramadoCuotaCompanion.insert(
                descuentoProgramadoId: descuento.id,
                numeroCuota: cuota.numeroCuota,
                fechaProgramada: cuota.fechaProgramada,
                importeProgramado: cuota.importe,
              ),
            );
      }

      // Desembolso real (típicamente un préstamo) — la SEÑAL es
      // `cuentaFinancieraId != null`, nunca `tipo`. El concepto del
      // Egreso embebe el folio, así que el Egreso se crea DESPUÉS de
      // insertar la fila (mismo orden que `TiempoExtraRepositoryImpl.
      // registrar`).
      if (cuentaFinancieraId != null) {
        final folioEgreso = await _codigoSecuencia.siguienteCodigo('egreso');
        final egreso = await _egresoRepository.crear(
          folioEgreso: folioEgreso,
          monto: importeOriginal,
          fecha: fechaRegistro,
          cuentaFinancieraId: cuentaFinancieraId,
          formaPago: formaPagoEgreso ?? 'transferencia',
          beneficiario: beneficiarioEgreso,
          concepto: 'Descuento programado $folio — entrega de dinero',
          actorUsuarioId: actorUsuarioId,
        );
        descuento = await (_db.update(_db.descuentoProgramadoEmpleado)
              ..where((t) => t.id.equals(descuento.id)))
            .writeReturning(
              DescuentoProgramadoEmpleadoCompanion(
                cuentaFinancieraId: Value(cuentaFinancieraId),
                egresoId: Value(egreso.id),
              ),
            )
            .then((rows) => rows.single);
      }

      await _registrarMovimiento(
        descuentoProgramadoId: descuento.id,
        tipoMovimiento: 'otorgamiento',
        importe: importeOriginal,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'numeroCuotas': cuotas.length,
          'huboDesembolso': cuentaFinancieraId != null,
        },
      );

      return descuento;
    });
  }

  @override
  Future<void> reservarCuotas({
    required List<String> cuotaIds,
    required String nominaEmpleadoId,
  }) async {
    if (cuotaIds.isEmpty) return;
    await (_db.update(_db.descuentoProgramadoCuota)
      ..where((t) => t.id.isIn(cuotaIds))).write(
      DescuentoProgramadoCuotaCompanion(
        estatus: const Value('reservada'),
        nominaEmpleadoId: Value(nominaEmpleadoId),
        updatedAt: Value(DateTime.now()),
      ),
    );
    for (final cuotaId in cuotaIds) {
      final cuota =
          await (_db.select(_db.descuentoProgramadoCuota)
            ..where((t) => t.id.equals(cuotaId))).getSingle();
      await _registrarMovimiento(
        descuentoProgramadoId: cuota.descuentoProgramadoId,
        cuotaId: cuotaId,
        tipoMovimiento: 'cuotaReservada',
        importe: cuota.importeProgramado,
        observacion: 'Reservada en renglón de Nómina.',
      );
    }
  }

  @override
  Future<void> aplicarCuotasReservadas({
    required String nominaEmpleadoId,
    String? actorUsuarioId,
  }) async {
    final reservadas = await listarCuotasReservadasPorRenglon(nominaEmpleadoId);
    if (reservadas.isEmpty) return;

    await (_db.update(_db.descuentoProgramadoCuota)
      ..where((t) => t.id.isIn([for (final c in reservadas) c.id]))).write(
      DescuentoProgramadoCuotaCompanion(
        estatus: const Value('aplicada'),
        fechaAplicacion: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );

    final porDescuento = <String, List<DescuentoProgramadoCuotaData>>{};
    for (final cuota in reservadas) {
      (porDescuento[cuota.descuentoProgramadoId] ??= []).add(cuota);
    }

    for (final entry in porDescuento.entries) {
      final descuento =
          await (_db.select(_db.descuentoProgramadoEmpleado)
            ..where((t) => t.id.equals(entry.key))).getSingle();
      final totalAplicado = entry.value.fold<int>(
        0,
        (s, c) => s + c.importeProgramado,
      );
      final nuevoSaldo = descuento.saldoPendiente - totalAplicado;
      await (_db.update(_db.descuentoProgramadoEmpleado)
        ..where((t) => t.id.equals(entry.key))).write(
        DescuentoProgramadoEmpleadoCompanion(
          saldoPendiente: Value(nuevoSaldo),
          estatus: Value(nuevoSaldo <= 0 ? 'liquidado' : descuento.estatus),
          updatedAt: Value(DateTime.now()),
        ),
      );
      for (final cuota in entry.value) {
        await _registrarMovimiento(
          descuentoProgramadoId: entry.key,
          cuotaId: cuota.id,
          tipoMovimiento: 'cuotaAplicada',
          importe: cuota.importeProgramado,
          actorUsuarioId: actorUsuarioId,
          observacion: 'Aplicada al confirmarse el pago del renglón de Nómina.',
        );
      }
    }
  }

  @override
  Future<void> revertirCuotasAplicadasPorCancelacionPago({
    required String nominaEmpleadoId,
    String? actorUsuarioId,
  }) async {
    final aplicadas =
        await (_db.select(_db.descuentoProgramadoCuota)..where(
          (t) =>
              t.nominaEmpleadoId.equals(nominaEmpleadoId) &
              t.estatus.equals('aplicada'),
        )).get();
    if (aplicadas.isEmpty) return;

    await (_db.update(_db.descuentoProgramadoCuota)
      ..where((t) => t.id.isIn([for (final c in aplicadas) c.id]))).write(
      DescuentoProgramadoCuotaCompanion(
        estatus: const Value('reservada'),
        fechaAplicacion: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );

    final porDescuento = <String, List<DescuentoProgramadoCuotaData>>{};
    for (final cuota in aplicadas) {
      (porDescuento[cuota.descuentoProgramadoId] ??= []).add(cuota);
    }
    for (final entry in porDescuento.entries) {
      final descuento =
          await (_db.select(_db.descuentoProgramadoEmpleado)
            ..where((t) => t.id.equals(entry.key))).getSingle();
      final totalRevertido = entry.value.fold<int>(
        0,
        (s, c) => s + c.importeProgramado,
      );
      final nuevoSaldo = descuento.saldoPendiente + totalRevertido;
      await (_db.update(_db.descuentoProgramadoEmpleado)
        ..where((t) => t.id.equals(entry.key))).write(
        DescuentoProgramadoEmpleadoCompanion(
          saldoPendiente: Value(nuevoSaldo),
          estatus: Value(
            descuento.estatus == 'liquidado' && nuevoSaldo > 0
                ? 'activo'
                : descuento.estatus,
          ),
          updatedAt: Value(DateTime.now()),
        ),
      );
      for (final cuota in entry.value) {
        await _registrarMovimiento(
          descuentoProgramadoId: entry.key,
          cuotaId: cuota.id,
          tipoMovimiento: 'cuotaRevertida',
          importe: cuota.importeProgramado,
          actorUsuarioId: actorUsuarioId,
          observacion: 'Revertida por cancelación de pago de Nómina.',
        );
      }
    }
  }

  @override
  Future<void> liberarCuotasDeRenglones(
    List<String> nominaEmpleadoIds, {
    String? descuentoProgramadoId,
    String? observacion,
    String? actorUsuarioId,
  }) async {
    if (nominaEmpleadoIds.isEmpty) return;

    final vinculadas =
        await (_db.select(_db.descuentoProgramadoCuota)..where(
          (t) {
            var condicion =
                t.nominaEmpleadoId.isIn(nominaEmpleadoIds) &
                t.estatus.isIn(['reservada', 'aplicada']);
            // Etapa 0 (corrección de bug real): sin este filtro, liberar
            // las cuotas de UN descuento (reprogramar/cancelar saldo)
            // también des-reservaba (o revertía) cuotas de OTRO
            // descuento del mismo empleado que compartiera el mismo
            // renglón de Nómina — contaminación cruzada entre
            // descuentos independientes.
            if (descuentoProgramadoId != null) {
              condicion = condicion & t.descuentoProgramadoId.equals(descuentoProgramadoId);
            }
            return condicion;
          },
        )).get();
    if (vinculadas.isEmpty) return;

    final aplicadas = vinculadas.where((c) => c.estatus == 'aplicada').toList();

    await (_db.update(_db.descuentoProgramadoCuota)
      ..where((t) => t.id.isIn([for (final c in vinculadas) c.id]))).write(
      DescuentoProgramadoCuotaCompanion(
        estatus: const Value('pendiente'),
        nominaEmpleadoId: const Value(null),
        fechaAplicacion: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );

    // Solo las que estaban `aplicada` habían decrecido `saldoPendiente`
    // — las `reservada` nunca lo tocaron, así que no hace falta
    // restaurar nada por ellas.
    final porDescuento = <String, List<DescuentoProgramadoCuotaData>>{};
    for (final cuota in aplicadas) {
      (porDescuento[cuota.descuentoProgramadoId] ??= []).add(cuota);
    }
    for (final entry in porDescuento.entries) {
      final descuento =
          await (_db.select(_db.descuentoProgramadoEmpleado)
            ..where((t) => t.id.equals(entry.key))).getSingle();
      final totalRevertido = entry.value.fold<int>(
        0,
        (s, c) => s + c.importeProgramado,
      );
      final nuevoSaldo = descuento.saldoPendiente + totalRevertido;
      await (_db.update(_db.descuentoProgramadoEmpleado)
        ..where((t) => t.id.equals(entry.key))).write(
        DescuentoProgramadoEmpleadoCompanion(
          saldoPendiente: Value(nuevoSaldo),
          estatus: Value(
            descuento.estatus == 'liquidado' && nuevoSaldo > 0
                ? 'activo'
                : descuento.estatus,
          ),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }

    for (final cuota in vinculadas) {
      await _registrarMovimiento(
        descuentoProgramadoId: cuota.descuentoProgramadoId,
        cuotaId: cuota.id,
        tipoMovimiento: 'cuotaRevertida',
        importe: cuota.importeProgramado,
        actorUsuarioId: actorUsuarioId,
        observacion:
            observacion ??
            'Revertida a pendiente: la Nómina que la contenía fue eliminada.',
      );
    }
  }

  @override
  Future<void> reprogramarCuotasPendientes({
    required String descuentoProgramadoId,
    required List<({int numeroCuota, DateTime fechaProgramada, int importe})>
    nuevoPlan,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final actuales = await listarCuotas(descuentoProgramadoId);
      final reprogramables =
          actuales
              .where(
                (c) => c.estatus == 'pendiente' || c.estatus == 'reservada',
              )
              .toList();

      final planAnterior = [
        for (final c in reprogramables)
          {
            'numeroCuota': c.numeroCuota,
            'fechaProgramada': c.fechaProgramada.toIso8601String(),
            'importe': c.importeProgramado,
          },
      ];

      // Libera primero cualquier `reservada` (ver el doc comment de
      // `liberarCuotasDeRenglones`) — nunca se reprograma una cuota
      // todavía vinculada a un renglón de Nómina vivo.
      final nominaEmpleadoIds =
          reprogramables
              .where(
                (c) => c.estatus == 'reservada' && c.nominaEmpleadoId != null,
              )
              .map((c) => c.nominaEmpleadoId!)
              .toSet()
              .toList();
      if (nominaEmpleadoIds.isNotEmpty) {
        await liberarCuotasDeRenglones(
          nominaEmpleadoIds,
          descuentoProgramadoId: descuentoProgramadoId,
          observacion: 'Liberada para reprogramación.',
          actorUsuarioId: actorUsuarioId,
        );
      }

      // Las cuotas reprogramadas se marcan `cancelada` — NUNCA se
      // borran físicamente: `DescuentoProgramadoMovimiento.cuotaId` es
      // `cascade` hacia esta tabla, así que un `DELETE` real destruiría
      // también su propio historial de movimientos (`cuotaReservada`/
      // `cuotaRevertida` recién escritos arriba), justo lo que el
      // punto 16 del pedido prohíbe ("nunca reescribir/perder
      // trazabilidad").
      await (_db.update(
        _db.descuentoProgramadoCuota,
      )..where((t) => t.id.isIn([for (final c in reprogramables) c.id]))).write(
        DescuentoProgramadoCuotaCompanion(
          estatus: const Value('cancelada'),
          updatedAt: Value(DateTime.now()),
        ),
      );
      for (final cuota in nuevoPlan) {
        await _db
            .into(_db.descuentoProgramadoCuota)
            .insert(
              DescuentoProgramadoCuotaCompanion.insert(
                descuentoProgramadoId: descuentoProgramadoId,
                numeroCuota: cuota.numeroCuota,
                fechaProgramada: cuota.fechaProgramada,
                importeProgramado: cuota.importe,
              ),
            );
      }

      await _registrarMovimiento(
        descuentoProgramadoId: descuentoProgramadoId,
        tipoMovimiento: 'reprogramacion',
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'planAnterior': planAnterior,
          'planNuevo': [
            for (final c in nuevoPlan)
              {
                'numeroCuota': c.numeroCuota,
                'fechaProgramada': c.fechaProgramada.toIso8601String(),
                'importe': c.importe,
              },
          ],
        },
      );
    });
  }

  @override
  Future<DescuentoProgramadoEmpleadoData> corregir({
    required String descuentoProgramadoId,
    String? tipo,
    String? descripcion,
    bool limpiarDescripcion = false,
    String? observaciones,
    bool limpiarObservaciones = false,
    DateTime? fechaRegistro,
    int? nuevoImporteOriginal,
    int? nuevoSaldoPendiente,
    List<({int numeroCuota, DateTime fechaProgramada, int importe})>?
    nuevoPlanCuotas,
    String? nuevoCuentaFinancieraId,
    bool limpiarCuentaFinancieraId = false,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final actual =
          await (_db.select(_db.descuentoProgramadoEmpleado)
            ..where((t) => t.id.equals(descuentoProgramadoId))).getSingle();

      final tipoFinal = tipo ?? actual.tipo;
      final descripcionFinal =
          limpiarDescripcion ? null : (descripcion ?? actual.descripcion);
      final observacionesFinal =
          limpiarObservaciones ? null : (observaciones ?? actual.observaciones);
      final fechaRegistroFinal = fechaRegistro ?? actual.fechaRegistro;
      final importeOriginalFinal = nuevoImporteOriginal ?? actual.importeOriginal;
      final saldoPendienteFinal = nuevoSaldoPendiente ?? actual.saldoPendiente;

      // Mismo mecanismo exacto que `reprogramarCuotasPendientes`: libera
      // primero cualquier `reservada` (nunca se toca una cuota todavía
      // vinculada a un renglón de Nómina vivo sin antes desvincularla),
      // marca `cancelada` (nunca `DELETE` — cascadearía sobre su propio
      // historial de `DescuentoProgramadoMovimiento`) las reprogramables
      // viejas, e inserta el plan nuevo. `nuevoPlanCuotas == null`
      // significa "el monto total no cambió, no toques ninguna cuota
      // futura"; `[]` significa "el nuevo saldo pendiente ya es 0, no
      // queda nada por programar".
      if (nuevoPlanCuotas != null) {
        final cuotas = await listarCuotas(descuentoProgramadoId);
        final reprogramables =
            cuotas
                .where(
                  (c) => c.estatus == 'pendiente' || c.estatus == 'reservada',
                )
                .toList();

        final nominaEmpleadoIds =
            reprogramables
                .where(
                  (c) => c.estatus == 'reservada' && c.nominaEmpleadoId != null,
                )
                .map((c) => c.nominaEmpleadoId!)
                .toSet()
                .toList();
        if (nominaEmpleadoIds.isNotEmpty) {
          await liberarCuotasDeRenglones(
            nominaEmpleadoIds,
            descuentoProgramadoId: descuentoProgramadoId,
            observacion: 'Liberada para corrección del monto total.',
            actorUsuarioId: actorUsuarioId,
          );
        }

        await (_db.update(_db.descuentoProgramadoCuota)..where(
          (t) => t.id.isIn([for (final c in reprogramables) c.id]),
        )).write(
          DescuentoProgramadoCuotaCompanion(
            estatus: const Value('cancelada'),
            updatedAt: Value(DateTime.now()),
          ),
        );
        for (final cuota in nuevoPlanCuotas) {
          await _db
              .into(_db.descuentoProgramadoCuota)
              .insert(
                DescuentoProgramadoCuotaCompanion.insert(
                  descuentoProgramadoId: descuentoProgramadoId,
                  numeroCuota: cuota.numeroCuota,
                  fechaProgramada: cuota.fechaProgramada,
                  importeProgramado: cuota.importe,
                ),
              );
        }
      }

      final estatusFinal = saldoPendienteFinal <= 0 ? 'liquidado' : 'activo';

      // Sincronización del desembolso — solo si YA existe un Egreso
      // vinculado (nunca se crea uno donde no había, ver el doc comment
      // de la interfaz). Dos llamadas separadas (cuenta / monto), mismo
      // criterio que `TiempoExtraRepositoryImpl._aplicarTransicionOrigen`
      // para su rama Cuenta→Cuenta.
      final cuentaFinancieraIdFinal =
          limpiarCuentaFinancieraId ? null : (nuevoCuentaFinancieraId ?? actual.cuentaFinancieraId);
      if (actual.egresoId != null) {
        if (nuevoCuentaFinancieraId != null || limpiarCuentaFinancieraId) {
          await _egresoRepository.corregir(
            egresoId: actual.egresoId!,
            cuentaFinancieraId: nuevoCuentaFinancieraId,
            limpiarCuentaFinancieraId: limpiarCuentaFinancieraId,
            motivo: motivo,
            actorUsuarioId: actorUsuarioId,
          );
        }
        if (importeOriginalFinal != actual.importeOriginal) {
          await _egresoRepository.corregirMonto(
            egresoId: actual.egresoId!,
            nuevoMonto: importeOriginalFinal,
            motivo: motivo,
            actorUsuarioId: actorUsuarioId,
          );
        }
      }

      await (_db.update(_db.descuentoProgramadoEmpleado)
        ..where((t) => t.id.equals(descuentoProgramadoId))).write(
        DescuentoProgramadoEmpleadoCompanion(
          tipo: Value(tipoFinal),
          descripcion: Value(descripcionFinal),
          observaciones: Value(observacionesFinal),
          fechaRegistro: Value(fechaRegistroFinal),
          importeOriginal: Value(importeOriginalFinal),
          saldoPendiente: Value(saldoPendienteFinal),
          estatus: Value(estatusFinal),
          cuentaFinancieraId: Value(cuentaFinancieraIdFinal),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final diff = DiffEvento()
        ..anotar('tipo', actual.tipo, tipoFinal)
        ..anotar('descripcion', actual.descripcion, descripcionFinal)
        ..anotar('observaciones', actual.observaciones, observacionesFinal)
        ..anotar('fechaRegistro', actual.fechaRegistro, fechaRegistroFinal)
        ..anotar('importeOriginal', actual.importeOriginal, importeOriginalFinal)
        ..anotar('saldoPendiente', actual.saldoPendiente, saldoPendienteFinal)
        ..anotar('estatus', actual.estatus, estatusFinal)
        ..anotar('cuentaFinancieraId', actual.cuentaFinancieraId, cuentaFinancieraIdFinal);
      if (diff.hayCambios) {
        await _registrarMovimiento(
          descuentoProgramadoId: descuentoProgramadoId,
          tipoMovimiento: 'correccion',
          observacion: motivo,
          actorUsuarioId: actorUsuarioId,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
        );
      }

      return (await obtenerPorId(descuentoProgramadoId))!;
    });
  }

  @override
  Future<void> cancelarSaldo({
    required String descuentoProgramadoId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final descuento =
          await (_db.select(_db.descuentoProgramadoEmpleado)
            ..where((t) => t.id.equals(descuentoProgramadoId))).getSingle();
      final cuotas = await listarCuotas(descuentoProgramadoId);
      final cancelables =
          cuotas
              .where(
                (c) => c.estatus == 'pendiente' || c.estatus == 'reservada',
              )
              .toList();

      final reservadas =
          cancelables
              .where(
                (c) => c.estatus == 'reservada' && c.nominaEmpleadoId != null,
              )
              .map((c) => c.nominaEmpleadoId!)
              .toSet()
              .toList();
      if (reservadas.isNotEmpty) {
        await liberarCuotasDeRenglones(
          reservadas,
          descuentoProgramadoId: descuentoProgramadoId,
          observacion: 'Liberada por cancelación de saldo.',
          actorUsuarioId: actorUsuarioId,
        );
      }

      await (_db.update(_db.descuentoProgramadoCuota)
        ..where((t) => t.id.isIn([for (final c in cancelables) c.id]))).write(
        DescuentoProgramadoCuotaCompanion(
          estatus: const Value('cancelada'),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final totalCancelado = cancelables.fold<int>(
        0,
        (s, c) => s + c.importeProgramado,
      );
      await (_db.update(_db.descuentoProgramadoEmpleado)
        ..where((t) => t.id.equals(descuentoProgramadoId))).write(
        DescuentoProgramadoEmpleadoCompanion(
          saldoPendiente: const Value(0),
          estatus: const Value('cancelado'),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // Si hubo un desembolso real y NADA se recuperó todavía, cancelar
      // también revierte ese Egreso — nada downstream depende de él, así
      // que equivale a "esto nunca debió registrarse" (mismo criterio
      // que Compra/TiempoExtra). Si algo YA se recuperó vía Nómina, el
      // Egreso nunca se toca — el desembolso histórico ocurrió
      // realmente y esto se vuelve condonación pura. Ver el doc comment
      // de la interfaz.
      final nadaRecuperadoTodavia = descuento.saldoPendiente == descuento.importeOriginal;
      final egresoRevertido = nadaRecuperadoTodavia && descuento.egresoId != null;
      if (egresoRevertido) {
        await _egresoRepository.cancelar(
          egresoId: descuento.egresoId!,
          motivo: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      }

      await _registrarMovimiento(
        descuentoProgramadoId: descuentoProgramadoId,
        tipoMovimiento: 'cancelacion',
        importe: totalCancelado,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'saldoCancelado': totalCancelado,
          'saldoRecuperadoPrevio':
              descuento.importeOriginal - descuento.saldoPendiente,
          'egresoRevertido': egresoRevertido,
        },
      );
    });
  }

  @override
  Future<ResumenEliminacionDescuentoProgramado> obtenerResumenEliminacionFisica(
    String descuentoProgramadoId,
  ) async {
    final descuento = await obtenerPorId(descuentoProgramadoId);
    if (descuento == null)
      return const ResumenEliminacionDescuentoProgramado(existe: false);

    final cuotas = await listarCuotas(descuentoProgramadoId);
    final aplicadas = cuotas.where((c) => c.estatus == 'aplicada').toList();
    if (aplicadas.isNotEmpty) {
      return ResumenEliminacionDescuentoProgramado(
        existe: true,
        detalleBloqueo:
            'Ya tiene ${aplicadas.length} cuota(s) aplicada(s) en Nómina — no puede eliminarse.',
      );
    }
    // Mismo bloqueo que ya usa `NominaRepositoryImpl.eliminarRenglon` —
    // una cuota `reservada` sigue vinculada a un renglón de Nómina vivo
    // (Borrador/Cerrada, aún no pagada); borrar el descuento debajo de
    // esa reserva la dejaría apuntando a una fila inexistente.
    final reservadas = cuotas.where((c) => c.estatus == 'reservada').toList();
    if (reservadas.isNotEmpty) {
      return ResumenEliminacionDescuentoProgramado(
        existe: true,
        detalleBloqueo:
            'Tiene ${reservadas.length} cuota(s) reservada(s) en una Nómina viva — libérela primero.',
      );
    }
    return const ResumenEliminacionDescuentoProgramado(existe: true);
  }

  @override
  Future<EliminarDescuentoProgramadoFisicamenteResultado> eliminarFisicamente({
    required String descuentoProgramadoId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final descuento = await obtenerPorId(descuentoProgramadoId);
    if (descuento == null)
      return EliminarDescuentoProgramadoFisicamenteNoExiste();

    final resumen = await obtenerResumenEliminacionFisica(
      descuentoProgramadoId,
    );
    if (resumen.bloqueado) {
      return EliminarDescuentoProgramadoFisicamenteTieneDependencias(
        resumen.detalleBloqueo!,
      );
    }

    await _db.transaction(() async {
      final cuotas = await listarCuotas(descuentoProgramadoId);
      final movimientos = await listarMovimientos(descuentoProgramadoId);
      // Por la invariante de `cancelarSaldo` (ver su doc comment): al
      // llegar aquí (ya `cancelado`, sin cuotas `aplicada`/`reservada`),
      // un Egreso vinculado siempre está ya `cancelado` — esta operación
      // solo lo snapshotea y lo borra, nunca decide si cancelarlo.
      final egreso =
          descuento.egresoId == null
              ? null
              : await (_db.select(_db.egreso)..where((t) => t.id.equals(descuento.egresoId!))).getSingleOrNull();

      final snapshot = <String, Object?>{
        'descuento': descuento.toJson(),
        'cuotas': [for (final c in cuotas) c.toJson()],
        'movimientos': [for (final m in movimientos) m.toJson()],
        if (egreso != null) 'egreso': egreso.toJson(),
      };

      await _db
          .into(_db.eliminacionFisicaEvento)
          .insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'descuentoProgramado',
              entidadIdOriginal: descuentoProgramadoId,
              fechaHora: DateTime.now(),
              motivo: motivo,
              actorUsuarioId: Value(actorUsuarioId),
              snapshotJson: jsonEncode(snapshot),
            ),
          );

      // Cascada de FK borra sus `DescuentoProgramadoCuota` y
      // `DescuentoProgramadoMovimiento` automáticamente.
      await (_db.delete(_db.descuentoProgramadoEmpleado)
        ..where((t) => t.id.equals(descuentoProgramadoId))).go();

      // Egreso propio — después, `restrict` hacia Egreso.
      if (egreso != null) {
        await (_db.delete(_db.egreso)..where((t) => t.id.equals(egreso.id))).go();
      }
    });

    return EliminarDescuentoProgramadoFisicamenteExitoso();
  }
}
