import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva de la Etapa 5E (`schemaVersion` 21 → 22): crea
/// `FichaTecnicaEmpleado` (ver su doc comment) — el historial append-only
/// de fichas técnicas generadas para un Empleado.
///
/// Tabla enteramente nueva — ningún origen anterior pudo haberla creado
/// ya, así que `to >= 22 && from <= 21` es seguro sin acotar un origen
/// exacto (mismo criterio que `AsignacionServicio` en la Etapa 5D). El
/// renglón nuevo de `CodigoSecuencia('ficha_tecnica')` se siembra vía
/// `runSeed()` normal — `codigo_secuencia` ya existe desde
/// `schemaVersion` 1 en todo snapshot histórico, sin riesgo de "no such
/// table".
Future<void> migrarFichaTecnicaEmpleadoV22(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    await m.createTable(db.fichaTecnicaEmpleado);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 22: foreign_key_check reportó '
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
        'Migración a schemaVersion 22: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
