import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva de la Etapa 5B (`schemaVersion` 18 → 19): agrega
/// las 13 columnas nullable de Perfil psicológico (3), Estudio
/// socioeconómico (3) y Antidoping (7) a `Empleado` — ninguna lleva
/// `CHECK`/`UNIQUE`/`DEFAULT` no trivial, así que `ALTER TABLE ADD
/// COLUMN` (`Migrator.addColumn`) basta, sin recrear la tabla (a
/// diferencia de todas las migraciones estructurales de `Attachment`/
/// `Direccion` en la Etapa 5A).
///
/// **Solo aplica con `from == 18` exacto — nunca `from <= 18`.** Mismo
/// gotcha ya documentado varias veces en este archivo (`migrarServicioV7`,
/// `migrarAttachmentV17`, etc.): cualquier instalación con `from <= 17`
/// pasa por el bloque `to >= 18` de `onUpgrade`, que crea `empleado` vía
/// `m.createTable(empleado)` — y esa llamada siempre lee la forma
/// *actual* de la clase Dart, que para cuando existe este archivo YA
/// incluye las 13 columnas de la Etapa 5B. Agregar esas columnas otra
/// vez aquí, para ese mismo origen, lanzaría "duplicate column name".
/// Solo una instalación que ya estaba exactamente en schemaVersion 18
/// (nunca pasó por ese `m.createTable` con la forma nueva) todavía
/// tiene la forma vieja y necesita este paso.
Future<void> migrarEmpleadoV19(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    await m.addColumn(db.empleado, db.empleado.fechaEvaluacionPsicologica);
    await m.addColumn(db.empleado, db.empleado.resumenPsicologico);
    await m.addColumn(db.empleado, db.empleado.observacionesPsicologico);
    await m.addColumn(db.empleado, db.empleado.fechaEstudioSocioeconomico);
    await m.addColumn(db.empleado, db.empleado.resumenEstudioSocioeconomico);
    await m.addColumn(db.empleado, db.empleado.observacionesEstudioSocioeconomico);
    await m.addColumn(db.empleado, db.empleado.fechaAntidoping);
    await m.addColumn(db.empleado, db.empleado.resultadoAmp);
    await m.addColumn(db.empleado, db.empleado.resultadoBzd);
    await m.addColumn(db.empleado, db.empleado.resultadoCoc);
    await m.addColumn(db.empleado, db.empleado.resultadoMet);
    await m.addColumn(db.empleado, db.empleado.resultadoOpi);
    await m.addColumn(db.empleado, db.empleado.observacionesAntidoping);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración de Empleado a schemaVersion 19: foreign_key_check reportó '
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
        'Migración de Empleado a schemaVersion 19: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
