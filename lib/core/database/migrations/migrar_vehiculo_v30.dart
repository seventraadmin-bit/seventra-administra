import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva de la Etapa 8A (`schemaVersion` 29 → 30): funda el
/// dominio Vehículos — crea `Vehiculo`/`VehiculoAttachment` junto con
/// los dos índices únicos parciales de `Vehiculo`
/// (`idx_vehiculo_placas_unica`/`idx_vehiculo_vin_unico`), que
/// refuerzan a nivel de BD "placas/VIN únicos solo cuando se capturan"
/// — mismo criterio y mismo mecanismo que `migrarAsignacionV28` (Etapa
/// 7B).
///
/// Tablas enteramente nuevas — ningún origen anterior pudo haberlas
/// creado ya, así que `to >= 30 && from <= 29` es seguro sin acotar un
/// origen exacto.
///
/// `Migrator.createTable` **no** crea automáticamente los índices
/// declarados vía `@TableIndex.sql` — hace falta `m.createIndex(...)`
/// explícito.
Future<void> migrarVehiculoV30(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    await m.createTable(db.vehiculo);
    await m.createIndex(db.idxVehiculoPlacasUnica);
    await m.createIndex(db.idxVehiculoVinUnico);
    await m.createTable(db.vehiculoAttachment);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 30: foreign_key_check reportó '
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
        'Migración a schemaVersion 30: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
