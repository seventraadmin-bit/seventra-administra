import 'package:drift/drift.dart';

import '../app_database.dart';

/// Columnas de `DocumentoPorEmitir` tal como existían en la Etapa 4I.1
/// (antes de las 9 columnas aditivas de la 4I.2.1) — sin cambios de
/// nombre ni de tipo, solo se usan para copiar filas.
const _columnasDocumentoPorEmitirAnteriores = [
  'id', 'created_at', 'updated_at', 'ciclo_vida_registro',
  'codigo', 'cliente_id', 'entidad_fiscal_id', 'tipo_documento', 'agrupacion',
  'metodo', 'requiere_complemento', 'periodo_inicio', 'periodo_fin',
  'fecha_emision_programada', 'fecha_procesamiento_programada', 'fecha_pago_esperado_programada',
  'generation_key', 'importe_base_esperado', 'ajuste_manual', 'motivo_ajuste',
  'importe_final_esperado', 'estatus', 'motivo_estatus', 'observaciones',
];

/// Migración estructural de la Etapa 4I.2.1 (`schemaVersion` 11 → 12):
/// agrega el CHECK `importe_emitido IS NULL OR importe_emitido >= 0` —
/// requiere recrear la tabla porque SQLite no permite agregar una
/// restricción `CHECK` a nivel de tabla vía `ALTER TABLE ... ADD
/// COLUMN` (esa cláusula solo agrega la columna misma, nunca toca las
/// restricciones de tabla). Las 9 columnas nuevas en sí sí podrían
/// agregarse con `ADD COLUMN`, pero como de todas formas hace falta
/// recrear la tabla por el `CHECK`, se agregan aquí mismo para no
/// duplicar la lógica en dos pasos separados del `onUpgrade`.
///
/// `DocumentoPorEmitir` es tabla *referenciada* (por
/// `DocumentoPorEmitirServicio`/`Configuracion`/`Linea`/`Correo`/
/// `CorreoEnvio`/`Evento`) — mismo riesgo real ya documentado en
/// `migrarServicioV6`: desde SQLite 3.25, `ALTER TABLE ... RENAME TO`
/// reescribe automáticamente las FKs de otras tablas hacia el nombre
/// temporal. Se usa la misma corrección (`PRAGMA legacy_alter_table =
/// ON` durante el `RENAME`).
///
/// Solo aplica a instalaciones que ya tenían `DocumentoPorEmitir`
/// físicamente creado con la forma de la Etapa 4I.1 (`from == 11`
/// exacto) — un origen `from <= 10` ya la crea con la forma *actual*
/// (incluida esta migración) en el paso `to >= 11` del `onUpgrade`,
/// que corre antes.
Future<void> migrarDocumentoPorEmitirV12(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final conteoAntes = await db
        .customSelect('SELECT COUNT(*) AS n FROM documento_por_emitir')
        .map((r) => r.data['n'] as int)
        .getSingle();

    // Evita que SQLite reescriba las FKs de las tablas hijas hacia el
    // nombre temporal — ver nota arriba.
    await db.customStatement('PRAGMA legacy_alter_table = ON');
    await db.customStatement('ALTER TABLE documento_por_emitir RENAME TO documento_por_emitir_old');

    // Crea `documento_por_emitir` (nombre real, ya libre) con la forma
    // *actual* de la clase Dart: las 9 columnas nuevas + su CHECK.
    await m.createTable(db.documentoPorEmitir);

    final columnas = _columnasDocumentoPorEmitirAnteriores.join(', ');
    await db.customStatement(
      'INSERT INTO documento_por_emitir ($columnas) SELECT $columnas FROM documento_por_emitir_old',
    );

    final conteoDespues = await db
        .customSelect('SELECT COUNT(*) AS n FROM documento_por_emitir')
        .map((r) => r.data['n'] as int)
        .getSingle();
    if (conteoDespues != conteoAntes) {
      throw StateError(
        'Migración de DocumentoPorEmitir a schemaVersion 12: se esperaban $conteoAntes filas '
        'copiadas, se encontraron $conteoDespues. Migración abortada.',
      );
    }

    await db.customStatement('DROP TABLE documento_por_emitir_old');
    await db.customStatement('PRAGMA legacy_alter_table = OFF');

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración de DocumentoPorEmitir a schemaVersion 12: foreign_key_check reportó '
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
        'Migración de DocumentoPorEmitir a schemaVersion 12: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
