import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración de la Bóveda de Accesos del Maestro (`schemaVersion` 44 →
/// 45): dos tablas enteramente nuevas, `BovedaCredencial` y
/// `BovedaCredencialEvento` — puramente aditiva, ninguna tabla ni
/// columna existente se toca.
Future<void> migrarBovedaV45(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    await m.createTable(db.bovedaCredencial);
    await m.createTable(db.bovedaCredencialEvento);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 45: foreign_key_check reportó '
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
        'Migración a schemaVersion 45: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
