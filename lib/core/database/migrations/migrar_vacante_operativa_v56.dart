import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva (Etapa 15, rediseño del Dashboard gerencial):
/// tabla enteramente nueva `VacanteOperativa` — bitácora del ciclo
/// "posición cubierta → vacante → nuevamente cubierta" (ver el doc
/// comment completo de la tabla). Ninguna tabla ni columna existente se
/// toca; no requiere backfill — se mantiene hacia adelante desde este
/// cambio (ver `AsignacionServicioRepositoryImpl._reconciliarVacante`).
Future<void> migrarVacanteOperativaV56(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    await m.createTable(db.vacanteOperativa);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 56: foreign_key_check reportó '
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
        'Migración a schemaVersion 56: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
