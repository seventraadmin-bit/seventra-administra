import 'package:drift/drift.dart';

import '../app_database.dart';

/// Estructural (Etapa 7C): `AsignacionAttachment` cambia su llave
/// primaria de simple (`attachmentId`) a compuesta (`attachmentId`,
/// `asignacionId`) — ver el doc comment de la tabla: un resguardo
/// real cubre normalmente varios artículos con una sola firma, así
/// que un mismo `attachmentId` necesita poder unirse a varias
/// Asignaciones. `ALTER TABLE` no puede cambiar una llave primaria,
/// así que se recrea; como la tabla nunca tuvo filas desde que se
/// creó en la Etapa 7B (`schemaVersion` 28), no hay backfill que
/// hacer — solo dropear y volver a crear con la forma actual.
///
/// Gotcha de rango de siempre: cualquier `from <= 27` ya crea la
/// tabla con la forma *actual* (llave compuesta) en el bloque `to >=
/// 28` de `onUpgrade` (`m.createTable` siempre lee la clase Dart de
/// hoy, nunca la forma histórica) — por eso este paso corre solo
/// para `from == 28` exacto, nunca `from <= 28`.
Future<void> migrarAsignacionAttachmentV29(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    await m.deleteTable('asignacion_attachment');
    await m.createTable(db.asignacionAttachment);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 29: foreign_key_check reportó '
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
        'Migración a schemaVersion 29: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
