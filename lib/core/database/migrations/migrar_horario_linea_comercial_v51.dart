import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración de la Etapa 15 (Horario personalizado de línea comercial,
/// `schemaVersion` 50 → 51): tabla enteramente nueva
/// `ServicioLineaComercialVigenciaHorario`, día por día del horario
/// personalizado de una vigencia cuando su `modalidadTurnoId` es
/// Personalizado. Puramente aditiva — ninguna tabla ni columna
/// existente se toca.
Future<void> migrarHorarioLineaComercialV51(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    await m.createTable(db.servicioLineaComercialVigenciaHorario);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 51: foreign_key_check reportó '
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
        'Migración a schemaVersion 51: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
