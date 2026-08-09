import 'package:drift/drift.dart';

import '../app_database.dart';

/// Columnas de `Attachment` tal como existían antes de la Etapa 4J.2
/// (13 en total, forma de la Etapa 4I.2.2) — sin cambios de nombre ni
/// de tipo, solo se usan para copiar filas.
const _columnasAttachmentAnteriores = [
  'id', 'empresa_id', 'cliente_id', 'documento_por_emitir_id', 'categoria',
  'original_file_name', 'stored_file_name', 'path', 'mime_type', 'size_bytes',
  'hash', 'estado', 'created_at',
];

/// Migración estructural de la Etapa 4J.2 (`schemaVersion` 2 a 14 →
/// 15): agrega `pagoId` (comprobante de pago) y extiende el arco
/// exclusivo a 4 vías — requiere recrear la tabla porque SQLite no
/// permite modificar un `CHECK` de tabla vía `ALTER TABLE ... ADD
/// COLUMN` (mismo motivo que `migrarAttachmentV13`).
///
/// `Attachment` sigue siendo tabla *referenciada* por
/// `Empresa.logoAttachmentId` — misma corrección de siempre
/// (`PRAGMA legacy_alter_table = ON`).
///
/// Solo aplica a instalaciones con `Attachment` físicamente creada con
/// alguna forma anterior (`from` 2 a 14) — un origen `from == 1` ya la
/// crea con la forma *actual* en `_createEtapa4ATables`, que corre
/// antes en el mismo `onUpgrade` (mismo gotcha de siempre).
Future<void> migrarAttachmentV15(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final conteoAntes = await db
        .customSelect('SELECT COUNT(*) AS n FROM attachment')
        .map((r) => r.data['n'] as int)
        .getSingle();

    // Evita que SQLite reescriba la FK de Empresa.logo_attachment_id
    // hacia el nombre temporal — ver nota arriba.
    await db.customStatement('PRAGMA legacy_alter_table = ON');
    await db.customStatement('ALTER TABLE attachment RENAME TO attachment_old');

    // Crea `attachment` (nombre real, ya libre) con la forma *actual*
    // de la clase Dart: la columna `pago_id` + el CHECK de 4 vías.
    await m.createTable(db.attachment);

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
        'Migración de Attachment a schemaVersion 15: se esperaban $conteoAntes filas '
        'copiadas, se encontraron $conteoDespues. Migración abortada.',
      );
    }

    await db.customStatement('DROP TABLE attachment_old');
    await db.customStatement('PRAGMA legacy_alter_table = OFF');

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración de Attachment a schemaVersion 15: foreign_key_check reportó '
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
        'Migración de Attachment a schemaVersion 15: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
