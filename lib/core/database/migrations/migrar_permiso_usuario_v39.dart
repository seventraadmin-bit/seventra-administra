import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración de la Etapa 11B (`schemaVersion` 38 → 39): agrega
/// `PermisoUsuario` — permisos dinámicos por Usuario (tabla puente,
/// código libre `'modulo.accion'`, sin columnas rígidas por módulo).
///
/// Tabla enteramente nueva — ningún origen anterior pudo haberla
/// creado ya, así que `from <= 38` es seguro sin acotar un origen
/// exacto. El Maestro no recibe filas aquí (sus permisos se calculan
/// en memoria, ver `modulos_permiso.dart`), así que no hay backfill.
Future<void> migrarPermisoUsuarioV39(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    await m.createTable(db.permisoUsuario);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 39: foreign_key_check reportó '
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
        'Migración a schemaVersion 39: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
