import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva de la Etapa 9B (`schemaVersion` 34 → 35): crea
/// `AsignacionLineaTelefonica`/`LineaTelefonicaEquipo` junto con el
/// índice único parcial de `AsignacionLineaTelefonica`
/// (`idx_asignacion_linea_telefonica_vigente`), que refuerza a nivel de
/// BD "una línea no puede tener dos asignaciones vigentes a la vez" —
/// mismo criterio y mismo mecanismo que `migrarAsignacionVehiculoV31`.
///
/// Tablas enteramente nuevas — ningún origen anterior pudo haberlas
/// creado ya, así que `to >= 35 && from <= 34` es seguro sin acotar un
/// origen exacto.
///
/// `Migrator.createTable` **no** crea automáticamente los índices
/// declarados vía `@TableIndex.sql` — hace falta `m.createIndex(...)`
/// explícito.
Future<void> migrarAsignacionLineaTelefonicaV35(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    await m.createTable(db.asignacionLineaTelefonica);
    await m.createIndex(db.idxAsignacionLineaTelefonicaVigente);
    await m.createTable(db.lineaTelefonicaEquipo);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 35: foreign_key_check reportó '
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
        'Migración a schemaVersion 35: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
