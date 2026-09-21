import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva (Etapa 15, "Descuentos Programados al Personal" —
/// préstamos + cobro de botas, integrados automáticamente con Nómina):
/// tres tablas enteramente nuevas
/// (`DescuentoProgramadoEmpleado`/`DescuentoProgramadoCuota`/
/// `DescuentoProgramadoMovimiento`), dos columnas nuevas en
/// `NominaEmpleado` (`descuentos_programados`/
/// `descuentos_programados_pendiente_revision`, mismo criterio exacto
/// que `descuentos_inventario`/`descuentos_inventario_pendiente_revision`
/// en `migrarDescuentoInventarioNominaV54`), y dos filas nuevas de
/// `CodigoSecuencia` (`descuentoProgramadoPrestamo` → `PRE`,
/// `descuentoProgramadoBotas` → `DES`). Ninguna tabla ni columna
/// existente se modifica ni se elimina; no requiere backfill — el
/// campo manual `NominaEmpleado.prestamo` histórico se conserva
/// intacto y se sigue mostrando (ver `RenglonNominaDetalleDialog`).
Future<void> migrarDescuentosPersonalV57(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final tablas = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name IN "
      "('descuento_programado_empleado', 'descuento_programado_cuota', 'descuento_programado_movimiento')",
    ).get();
    final tablasExistentes = tablas.map((fila) => fila.data['name']).toSet();

    if (!tablasExistentes.contains('descuento_programado_empleado')) {
      await m.createTable(db.descuentoProgramadoEmpleado);
    }
    if (!tablasExistentes.contains('descuento_programado_cuota')) {
      await m.createTable(db.descuentoProgramadoCuota);
    }
    if (!tablasExistentes.contains('descuento_programado_movimiento')) {
      await m.createTable(db.descuentoProgramadoMovimiento);
    }

    final columnasNominaEmpleado = await db.customSelect("PRAGMA table_info('nomina_empleado')").get();
    final nombresNominaEmpleado = columnasNominaEmpleado.map((fila) => fila.data['name']).toSet();
    if (!nombresNominaEmpleado.contains('descuentos_programados')) {
      await m.addColumn(db.nominaEmpleado, db.nominaEmpleado.descuentosProgramados);
    }
    if (!nombresNominaEmpleado.contains('descuentos_programados_pendiente_revision')) {
      await m.addColumn(db.nominaEmpleado, db.nominaEmpleado.descuentosProgramadosPendienteRevision);
    }

    await db.into(db.codigoSecuencia).insertOnConflictUpdate(
          CodigoSecuenciaCompanion.insert(entityType: 'descuentoProgramadoPrestamo', prefijo: 'PRE', digitos: 6),
        );
    await db.into(db.codigoSecuencia).insertOnConflictUpdate(
          CodigoSecuenciaCompanion.insert(entityType: 'descuentoProgramadoBotas', prefijo: 'DES', digitos: 6),
        );

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 57: foreign_key_check reportó '
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
        'Migración a schemaVersion 57: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
