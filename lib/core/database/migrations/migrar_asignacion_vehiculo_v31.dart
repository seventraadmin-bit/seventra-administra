import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva de la Etapa 8B (`schemaVersion` 30 → 31): crea
/// `AsignacionVehiculo`/`VehiculoKilometraje` junto con el índice único
/// parcial de `AsignacionVehiculo` (`idx_asignacion_vehiculo_vigente`),
/// que refuerza a nivel de BD "un vehículo no puede tener dos
/// asignaciones vigentes a la vez" — mismo criterio y mismo mecanismo
/// que `migrarAsignacionV28`/`migrarVehiculoV30`.
///
/// Tablas enteramente nuevas — ningún origen anterior pudo haberlas
/// creado ya, así que `to >= 31 && from <= 30` es seguro sin acotar un
/// origen exacto.
///
/// `Migrator.createTable` **no** crea automáticamente los índices
/// declarados vía `@TableIndex.sql` — hace falta `m.createIndex(...)`
/// explícito (gotcha real, ya mordió una vez en la Etapa 8A: ver el
/// doc comment de `migrarVehiculoV30`).
Future<void> migrarAsignacionVehiculoV31(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    await m.createTable(db.asignacionVehiculo);
    await m.createIndex(db.idxAsignacionVehiculoVigente);
    await m.createTable(db.vehiculoKilometraje);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 31: foreign_key_check reportó '
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
        'Migración a schemaVersion 31: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
