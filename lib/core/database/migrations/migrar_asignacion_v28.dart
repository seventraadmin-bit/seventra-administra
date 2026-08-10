import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva de la Etapa 7B (`schemaVersion` 27 → 28): crea
/// `Asignacion` (relación Inventario↔Empleado/Servicio, ver su doc
/// comment) junto con su índice único parcial
/// (`idx_asignacion_unidad_activa`), que refuerza a nivel de BD "una
/// unidad serializada no puede tener dos asignaciones activas a la
/// vez" — mismo criterio y mismo mecanismo que
/// `migrarAsignacionServicioV21` (Etapa 5D).
///
/// Tabla enteramente nueva — ningún origen anterior pudo haberla creado
/// ya, así que `to >= 28 && from <= 27` es seguro sin acotar un origen
/// exacto.
///
/// `Migrator.createTable` **no** crea automáticamente los índices
/// declarados vía `@TableIndex.sql` — hace falta `m.createIndex(...)`
/// explícito.
Future<void> migrarAsignacionV28(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    await m.createTable(db.asignacion);
    await m.createIndex(db.idxAsignacionUnidadActiva);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 28: foreign_key_check reportó '
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
        'Migración a schemaVersion 28: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
