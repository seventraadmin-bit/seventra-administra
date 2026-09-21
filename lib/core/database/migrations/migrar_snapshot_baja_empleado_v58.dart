import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva (Etapa 15, rediseño de Personal/Bajas): agrega el
/// snapshot de puesto/servicio/turno al momento EXACTO de la baja —
/// `Empleado.puestoNombreBaja/servicioNombreBaja/turnoNombreBaja`
/// (para el periodo vigente-o-recién-cerrado) y las mismas 3 columnas
/// en `EmpleadoPeriodoLaboral` (para periodos ya archivados por un
/// Reingreso posterior). Ninguna columna existente se modifica.
///
/// Backfill real, nunca inventado: para cada baja ya existente,
/// `servicioNombreBaja`/`turnoNombreBaja` se resuelven vía el JOIN
/// EXACTO `AsignacionServicio.empleadoId` + `motivoTermino ==
/// 'bajaEmpleado'` + `fechaTermino == fechaBaja` — la misma fecha que
/// `EmpleadoRepositoryImpl.registrarBajaLaboral` usa para cerrar esa
/// asignación en la misma transacción original, así que el cruce es
/// determinista, no una heurística aproximada. `puestoNombreBaja` para
/// una baja **vigente** (el Empleado nunca reingresó) se resuelve del
/// `puestoId` actual, que todavía no fue sobrescrito por ningún
/// Reingreso. Para periodos ya archivados en `EmpleadoPeriodoLaboral`
/// antes de esta migración, el puesto de ese momento ya se perdió (el
/// Reingreso posterior sobrescribió `Empleado.puestoId`) — queda
/// `NULL` a propósito, nunca inventado; servicio/turno de esos
/// periodos archivados sí se recupera con el mismo JOIN exacto.
Future<void> migrarSnapshotBajaEmpleadoV58(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final columnasEmpleado = await db.customSelect("PRAGMA table_info('empleado')").get();
    final nombresEmpleado = columnasEmpleado.map((fila) => fila.data['name']).toSet();
    if (!nombresEmpleado.contains('puesto_nombre_baja')) {
      await m.addColumn(db.empleado, db.empleado.puestoNombreBaja);
    }
    if (!nombresEmpleado.contains('servicio_nombre_baja')) {
      await m.addColumn(db.empleado, db.empleado.servicioNombreBaja);
    }
    if (!nombresEmpleado.contains('turno_nombre_baja')) {
      await m.addColumn(db.empleado, db.empleado.turnoNombreBaja);
    }

    final columnasPeriodo = await db.customSelect("PRAGMA table_info('empleado_periodo_laboral')").get();
    final nombresPeriodo = columnasPeriodo.map((fila) => fila.data['name']).toSet();
    if (!nombresPeriodo.contains('puesto_nombre')) {
      await m.addColumn(db.empleadoPeriodoLaboral, db.empleadoPeriodoLaboral.puestoNombre);
    }
    if (!nombresPeriodo.contains('servicio_nombre')) {
      await m.addColumn(db.empleadoPeriodoLaboral, db.empleadoPeriodoLaboral.servicioNombre);
    }
    if (!nombresPeriodo.contains('turno_nombre')) {
      await m.addColumn(db.empleadoPeriodoLaboral, db.empleadoPeriodoLaboral.turnoNombre);
    }

    // `fecha_baja`/`fecha_termino` se leen y comparan como el entero
    // crudo (segundos desde época) que Drift ya usa para almacenar
    // `DateTimeColumn` — nunca se hace un viaje de ida y vuelta por
    // `DateTime`/ISO-8601, que además tienen un formato de
    // serialización distinto al de esta columna.
    Future<({String? servicioNombre, String? turnoNombre})> resolverServicioTurnoDeBaja({
      required String empleadoId,
      required int fechaBajaEpoch,
    }) async {
      final filas = await db.customSelect(
        'SELECT s.nombre AS servicio_nombre, t.nombre AS turno_nombre '
        'FROM asignacion_servicio a '
        'JOIN servicio s ON s.id = a.servicio_id '
        'LEFT JOIN tipo_modalidad_turno t ON t.id = a.turno_id '
        "WHERE a.empleado_id = ? AND a.motivo_termino = 'bajaEmpleado' AND a.fecha_termino = ? "
        'LIMIT 1',
        variables: [Variable(empleadoId), Variable(fechaBajaEpoch)],
      ).get();
      if (filas.isEmpty) return (servicioNombre: null, turnoNombre: null);
      return (
        servicioNombre: filas.single.data['servicio_nombre'] as String?,
        turnoNombre: filas.single.data['turno_nombre'] as String?,
      );
    }

    // Backfill de bajas VIGENTES (Empleado.estatus == 'baja', nunca
    // reingresó) — puesto se resuelve del puntero actual, todavía
    // intacto.
    final empleadosDeBaja = await db.customSelect(
      "SELECT id, puesto_id, fecha_baja FROM empleado WHERE estatus = 'baja' AND fecha_baja IS NOT NULL",
    ).get();
    for (final fila in empleadosDeBaja) {
      final empleadoId = fila.data['id'] as String;
      final puestoId = fila.data['puesto_id'] as String?;
      final fechaBajaEpoch = fila.data['fecha_baja'] as int;

      String? puestoNombre;
      if (puestoId != null) {
        final puestoFilas =
            await db.customSelect('SELECT nombre FROM puesto WHERE id = ?', variables: [Variable(puestoId)]).get();
        if (puestoFilas.isNotEmpty) puestoNombre = puestoFilas.single.data['nombre'] as String?;
      }
      final servicioTurno = await resolverServicioTurnoDeBaja(empleadoId: empleadoId, fechaBajaEpoch: fechaBajaEpoch);

      await db.customStatement(
        'UPDATE empleado SET puesto_nombre_baja = ?, servicio_nombre_baja = ?, turno_nombre_baja = ? WHERE id = ?',
        [puestoNombre, servicioTurno.servicioNombre, servicioTurno.turnoNombre, empleadoId],
      );
    }

    // Backfill de periodos YA ARCHIVADOS (reingreso posterior) —
    // puesto no es recuperable (ver doc comment de esta función);
    // servicio/turno sí, con el mismo JOIN exacto.
    final periodosArchivados = await db.customSelect(
      'SELECT id, empleado_id, fecha_baja FROM empleado_periodo_laboral',
    ).get();
    for (final fila in periodosArchivados) {
      final periodoId = fila.data['id'] as int;
      final empleadoId = fila.data['empleado_id'] as String;
      final fechaBajaEpoch = fila.data['fecha_baja'] as int;

      final servicioTurno = await resolverServicioTurnoDeBaja(empleadoId: empleadoId, fechaBajaEpoch: fechaBajaEpoch);
      if (servicioTurno.servicioNombre == null && servicioTurno.turnoNombre == null) continue;

      await db.customStatement(
        'UPDATE empleado_periodo_laboral SET servicio_nombre = ?, turno_nombre = ? WHERE id = ?',
        [servicioTurno.servicioNombre, servicioTurno.turnoNombre, periodoId],
      );
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 58: foreign_key_check reportó '
        '${violacionesFk.length} violación(es) tras la migración. Migración abortada.',
      );
    }

    final resultadoIntegridad = await db
        .customSelect('PRAGMA integrity_check')
        .map((r) => r.data['integrity_check'] as String)
        .get();
    final integridadOk = resultadoIntegridad.length == 1 && resultadoIntegridad.single == 'ok';
    if (!integridadOk) {
      throw StateError(
        'Migración a schemaVersion 58: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
