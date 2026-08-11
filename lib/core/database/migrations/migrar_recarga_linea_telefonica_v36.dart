import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración de la Etapa 9C (`schemaVersion` 35 → 36): confirma que la
/// operación real de Telefonía en RISEG es prepago, sin planes ni
/// contratos — retira `LineaTelefonicaPlan` (creada en 9A bajo una
/// suposición que ya no aplica, nunca tuvo uso funcional real, ver
/// `linea_telefonica_plan_table.dart` en el historial de git) y funda
/// `RecargaLineaTelefonica`/`RecargaLineaTelefonicaAttachment` en su
/// lugar.
///
/// `Migrator.deleteTable` ejecuta `DROP TABLE IF EXISTS` — segura
/// incluso si una instalación real nunca llegó a tener filas en
/// `linea_telefonica_plan` (dato confirmado: la tabla nunca se usó en
/// producción). Los snapshots históricos `drift_schema_v34.json`/
/// `v35.json` **no se tocan** — reflejan correctamente que la tabla sí
/// existía en esas versiones; esta migración documenta su retiro hacia
/// adelante, no reescribe el pasado.
///
/// `RecargaLineaTelefonica`/`RecargaLineaTelefonicaAttachment` son
/// tablas enteramente nuevas, así que `from <= 35` es seguro sin
/// acotar un origen exacto.
Future<void> migrarRecargaLineaTelefonicaV36(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    await m.deleteTable('linea_telefonica_plan');
    await m.createTable(db.recargaLineaTelefonica);
    await m.createTable(db.recargaLineaTelefonicaAttachment);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 36: foreign_key_check reportó '
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
        'Migración a schemaVersion 36: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
