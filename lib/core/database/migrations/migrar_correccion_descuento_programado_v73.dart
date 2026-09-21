import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración de la Etapa 5 ("Descuentos programados — CRUD corregible,
/// trazabilidad y consistencia con Nómina"): puramente aditiva, sin
/// datos que migrar (`descuentos.corregir` ya existía en el catálogo
/// de permisos desde la Etapa 1 — se reutiliza tal cual para la nueva
/// corrección completa, no hay ningún código nuevo que otorgar
/// retroactivamente).
///
/// `descuento_programado_movimiento.estado_anterior`/`estado_nuevo`
/// (`TEXT` nullable, solo `Migrator.addColumn`) — mismo shape que
/// `NominaEvento`/`PagoNominaEvento`, para el nuevo `tipoMovimiento`
/// `correccion`. Filas históricas (`otorgamiento`/`cuotaReservada`/
/// `cuotaAplicada`/`cuotaRevertida`/`reprogramacion`/`cancelacion`)
/// quedan con ambos campos en `null` — nunca se rellenan
/// retroactivamente.
Future<void> migrarCorreccionDescuentoProgramadoV73(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final columnas = await db.customSelect("PRAGMA table_info('descuento_programado_movimiento')").get();
    final nombres = columnas.map((fila) => fila.data['name']).toSet();
    if (!nombres.contains('estado_anterior')) {
      await m.addColumn(db.descuentoProgramadoMovimiento, db.descuentoProgramadoMovimiento.estadoAnterior);
    }
    if (!nombres.contains('estado_nuevo')) {
      await m.addColumn(db.descuentoProgramadoMovimiento, db.descuentoProgramadoMovimiento.estadoNuevo);
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 73: foreign_key_check reportó '
        '${violacionesFk.length} violación(es). Migración abortada.',
      );
    }

    final resultadoIntegridad = await db
        .customSelect('PRAGMA integrity_check')
        .map((r) => r.data['integrity_check'] as String)
        .get();
    final integridadOk = resultadoIntegridad.length == 1 && resultadoIntegridad.single == 'ok';
    if (!integridadOk) {
      throw StateError(
        'Migración a schemaVersion 73: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
