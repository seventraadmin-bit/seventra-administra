import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva (Etapa 16, evolución visual del Design System):
/// agrega `Cliente.logoAttachmentId` — mismo puntero directo a
/// `Attachment` que ya usan `Empresa.logoAttachmentId`/
/// `Empleado.fotografiaAttachmentId`. La tabla puente
/// `ClienteAttachment` ya existía desde la Etapa 5A (creada junto con
/// el resto de tablas puente por dominio, nunca usada hasta ahora) —
/// esta migración no la toca, solo agrega la columna puntero en
/// `Cliente`. Nullable, sin backfill: ningún Cliente existente tiene
/// un logo que reconstruir, `NULL` es el valor correcto para todos los
/// registros ya existentes (caen al fallback de iniciales).
Future<void> migrarClienteLogoV59(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final columnas = await db.customSelect("PRAGMA table_info('cliente')").get();
    final nombres = columnas.map((fila) => fila.data['name']).toSet();
    if (!nombres.contains('logo_attachment_id')) {
      await m.addColumn(db.cliente, db.cliente.logoAttachmentId);
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 59: foreign_key_check reportó '
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
        'Migración a schemaVersion 59: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
