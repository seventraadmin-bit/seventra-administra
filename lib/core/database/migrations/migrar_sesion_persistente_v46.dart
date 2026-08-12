import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración de "Recuérdame en este equipo" (Etapa 15, `schemaVersion`
/// 45 → 46): tabla enteramente nueva `SesionPersistente` — puramente
/// aditiva, ninguna tabla ni columna existente se toca.
Future<void> migrarSesionPersistenteV46(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    await m.createTable(db.sesionPersistente);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 46: foreign_key_check reportó '
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
        'Migración a schemaVersion 46: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
