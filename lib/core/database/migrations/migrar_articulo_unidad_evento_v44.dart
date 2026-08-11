import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración de Inventario (`schemaVersion` 43 → 44): tabla enteramente
/// nueva `ArticuloUnidadEvento`, bitácora de `CorregirIdentidadUnidadUseCase`
/// (corrección de número de serie/marca/modelo/IMEI 1/IMEI 2 de una
/// `ArticuloUnidad` ya existente, cuando se capturó mal al darla de
/// alta). Puramente aditiva — ninguna tabla ni columna existente se
/// toca.
Future<void> migrarArticuloUnidadEventoV44(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    await m.createTable(db.articuloUnidadEvento);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 44: foreign_key_check reportó '
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
        'Migración a schemaVersion 44: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
