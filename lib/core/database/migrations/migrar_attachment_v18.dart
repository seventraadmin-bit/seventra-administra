import 'package:drift/drift.dart';

import '../app_database.dart';

/// Columnas de `Attachment` en su forma angosta, definitiva desde la
/// Etapa 5A — se usan para copiar filas hacia la tabla recreada.
const _columnasAttachmentAngostas = [
  'id', 'categoria', 'original_file_name', 'stored_file_name', 'path', 'mime_type', 'size_bytes',
  'hash', 'estado', 'created_at',
];

/// Los 7 dueños que vivían como columna directa en `Attachment` antes
/// de la Etapa 5A (tabla puente destino, columna de dueño en esa tabla,
/// columna de dueño original en `attachment`).
const _duenosAnteriores = [
  ('empresa_attachment', 'empresa_id', 'empresa_id'),
  ('cliente_attachment', 'cliente_id', 'cliente_id'),
  ('documento_por_emitir_attachment', 'documento_por_emitir_id', 'documento_por_emitir_id'),
  ('pago_attachment', 'pago_id', 'pago_id'),
  ('complemento_pago_attachment', 'complemento_pago_id', 'complemento_pago_id'),
  ('ingreso_attachment', 'ingreso_id', 'ingreso_id'),
  ('egreso_attachment', 'egreso_id', 'egreso_id'),
];

/// Migración estructural de la Etapa 5A (`schemaVersion` 2 a 17 → 18):
/// convierte `Attachment` de "arco exclusivo" (7 columnas de dueño +
/// `CHECK`) a tabla angosta de metadatos, migrando cada dueño existente
/// a su propia tabla puente (`PagoAttachment`, `IngresoAttachment`,
/// etc. — ver el doc comment de `attachment_table.dart` para la
/// justificación completa: el roadmap de RISEG ONE va a seguir
/// agregando dueños de documentos por años, y cada extensión anterior
/// requirió recrear esta tabla; con tablas puente, toda extensión
/// futura vuelve a ser aditiva).
///
/// Dos fases, misma transacción: (1) backfill — cada dueño no nulo se
/// copia a su tabla puente correspondiente (las 8 tablas puente, la de
/// Empleado incluida, ya existen — se crean antes de llamar a esta
/// función); (2) angostar — se recrea `attachment` sin las 7 columnas
/// de dueño ni el `CHECK`, mismo mecanismo de siempre
/// (`PRAGMA legacy_alter_table` para no perder la FK de
/// `Empresa.logoAttachmentId`, que sigue apuntando hacia esta tabla).
///
/// Solo aplica a instalaciones con `Attachment` físicamente creada con
/// alguna forma anterior (`from` 2 a 17) — un origen `from == 1` ya la
/// crea angosta en `_createEtapa4ATables`, que corre antes en el mismo
/// `onUpgrade`.
Future<void> migrarAttachmentV18(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final conteoAntes = await db
        .customSelect('SELECT COUNT(*) AS n FROM attachment')
        .map((r) => r.data['n'] as int)
        .getSingle();

    // Fase 1: backfill — cada Attachment con un dueño no nulo obtiene su
    // fila de unión en la tabla puente correspondiente. El `CHECK` de
    // arco exclusivo, vigente hasta este momento, ya garantizó que cada
    // fila tuviera exactamente un dueño no nulo — la suma de filas
    // migradas a las 7 tablas puente debe coincidir con `conteoAntes`.
    var totalMigrado = 0;
    for (final (tablaPuente, columnaPuente, columnaOrigen) in _duenosAnteriores) {
      await db.customStatement(
        'INSERT INTO $tablaPuente (attachment_id, $columnaPuente) '
        'SELECT id, $columnaOrigen FROM attachment WHERE $columnaOrigen IS NOT NULL',
      );
      final migrados = await db
          .customSelect('SELECT COUNT(*) AS n FROM $tablaPuente')
          .map((r) => r.data['n'] as int)
          .getSingle();
      totalMigrado += migrados;
    }
    if (totalMigrado != conteoAntes) {
      throw StateError(
        'Migración de Attachment a schemaVersion 18: se esperaban $conteoAntes filas '
        'con dueño migradas a tablas puente, se migraron $totalMigrado. Migración abortada.',
      );
    }

    // Fase 2: angostar — recrea `attachment` sin columnas de dueño.
    await db.customStatement('PRAGMA legacy_alter_table = ON');
    await db.customStatement('ALTER TABLE attachment RENAME TO attachment_old');

    await m.createTable(db.attachment);

    final columnas = _columnasAttachmentAngostas.join(', ');
    await db.customStatement(
      'INSERT INTO attachment ($columnas) SELECT $columnas FROM attachment_old',
    );

    final conteoDespues = await db
        .customSelect('SELECT COUNT(*) AS n FROM attachment')
        .map((r) => r.data['n'] as int)
        .getSingle();
    if (conteoDespues != conteoAntes) {
      throw StateError(
        'Migración de Attachment a schemaVersion 18: se esperaban $conteoAntes filas '
        'copiadas, se encontraron $conteoDespues. Migración abortada.',
      );
    }

    await db.customStatement('DROP TABLE attachment_old');
    await db.customStatement('PRAGMA legacy_alter_table = OFF');

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración de Attachment a schemaVersion 18: foreign_key_check reportó '
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
        'Migración de Attachment a schemaVersion 18: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
