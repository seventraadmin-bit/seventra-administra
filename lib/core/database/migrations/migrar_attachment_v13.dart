import 'package:drift/drift.dart';

import '../app_database.dart';

/// Columnas de `Attachment` tal como existían antes de la Etapa 4I.2.2
/// (10 en total) — sin cambios de nombre ni de tipo, solo se usan para
/// copiar filas.
const _columnasAttachmentAnteriores = [
  'id', 'empresa_id', 'cliente_id', 'original_file_name', 'stored_file_name',
  'path', 'mime_type', 'size_bytes', 'hash', 'created_at',
];

/// Migración estructural de la Etapa 4I.2.2 (`schemaVersion` 2 a 12 →
/// 13): agrega `documentoPorEmitirId`/`categoria`/`estado` y extiende
/// el arco exclusivo a 3 vías — requiere recrear la tabla porque
/// SQLite no permite modificar un `CHECK` de tabla vía `ALTER TABLE
/// ... ADD COLUMN` (mismo motivo que `migrarDocumentoPorEmitirV12`).
///
/// `Attachment` es tabla *referenciada* por `Empresa.logoAttachmentId`
/// — mismo riesgo real ya documentado en `migrarServicioV6`/
/// `migrarDocumentoPorEmitirV12`: `ALTER TABLE ... RENAME TO` reescribe
/// automáticamente las FKs de otras tablas hacia el nombre temporal. Se
/// usa la misma corrección (`PRAGMA legacy_alter_table = ON`).
///
/// Solo aplica a instalaciones con `Attachment` físicamente creada con
/// la forma anterior (`from` 2 a 12) — un origen `from == 1` ya la crea
/// con la forma *actual* en `_createEtapa4ATables`, que corre antes en
/// el mismo `onUpgrade` (mismo gotcha ya documentado en
/// `migrarServicioV7`/`migrarDocumentoPorEmitirV12`: `from <= 12`
/// completo duplicaría la recreación para ese origen).
Future<void> migrarAttachmentV13(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final conteoAntes = await db
        .customSelect('SELECT COUNT(*) AS n FROM attachment')
        .map((r) => r.data['n'] as int)
        .getSingle();

    // Evita que SQLite reescriba la FK de Empresa.logo_attachment_id
    // hacia el nombre temporal — ver nota arriba.
    await db.customStatement('PRAGMA legacy_alter_table = ON');
    await db.customStatement('ALTER TABLE attachment RENAME TO attachment_old');

    // Crea `attachment` (nombre real, ya libre) con la forma exacta que
    // tenía en schemaVersion 13: las 3 columnas nuevas + el CHECK de 3
    // vías. SQL fijo, no `m.createTable(db.attachment)` — desde la
    // Etapa 5A, `db.attachment` refleja la forma *actual y angosta* de
    // la tabla (sin columnas de dueño), no la forma histórica de esta
    // migración; delegar a `m.createTable` aquí recrearía la tabla ya
    // angosta demasiado pronto, perdiendo los dueños que
    // `migrarAttachmentV18` todavía necesita leer más adelante en la
    // misma cadena de `onUpgrade`.
    await db.customStatement('''
      CREATE TABLE "attachment" (
        "id" TEXT NOT NULL,
        "empresa_id" TEXT NULL,
        "cliente_id" TEXT NULL,
        "documento_por_emitir_id" TEXT NULL,
        "categoria" TEXT NULL,
        "original_file_name" TEXT NOT NULL,
        "stored_file_name" TEXT NOT NULL,
        "path" TEXT NOT NULL,
        "mime_type" TEXT NOT NULL,
        "size_bytes" INTEGER NOT NULL,
        "hash" TEXT NULL,
        "estado" TEXT NOT NULL DEFAULT 'activo',
        "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
        PRIMARY KEY ("id"),
        FOREIGN KEY (empresa_id) REFERENCES empresa (id) ON DELETE RESTRICT,
        FOREIGN KEY (cliente_id) REFERENCES cliente (id) ON DELETE RESTRICT,
        FOREIGN KEY (documento_por_emitir_id) REFERENCES documento_por_emitir (id) ON DELETE CASCADE,
        CHECK ((CASE WHEN empresa_id IS NOT NULL THEN 1 ELSE 0 END +
                CASE WHEN cliente_id IS NOT NULL THEN 1 ELSE 0 END +
                CASE WHEN documento_por_emitir_id IS NOT NULL THEN 1 ELSE 0 END) = 1)
      )
    ''');

    final columnas = _columnasAttachmentAnteriores.join(', ');
    await db.customStatement(
      'INSERT INTO attachment ($columnas) SELECT $columnas FROM attachment_old',
    );

    final conteoDespues = await db
        .customSelect('SELECT COUNT(*) AS n FROM attachment')
        .map((r) => r.data['n'] as int)
        .getSingle();
    if (conteoDespues != conteoAntes) {
      throw StateError(
        'Migración de Attachment a schemaVersion 13: se esperaban $conteoAntes filas '
        'copiadas, se encontraron $conteoDespues. Migración abortada.',
      );
    }

    await db.customStatement('DROP TABLE attachment_old');
    await db.customStatement('PRAGMA legacy_alter_table = OFF');

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración de Attachment a schemaVersion 13: foreign_key_check reportó '
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
        'Migración de Attachment a schemaVersion 13: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
