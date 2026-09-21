import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva ("Entrega múltiple de Inventario a Personal +
/// Resguardo único"): tabla enteramente nueva `Entrega` (cabecera
/// documental que agrupa varias `Asignacion` de un mismo acto de
/// entrega real), columna nueva `Asignacion.entregaId` (nullable —
/// ninguna Asignacion existente ni la que siga creando el diálogo
/// individual "Asignar artículo" se ve afectada), y una fila nueva de
/// `CodigoSecuencia` (`entrega` → `ENT`). Ninguna tabla ni columna
/// existente se modifica ni se elimina; no requiere backfill.
Future<void> migrarEntregaInventarioV60(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final tablas = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = 'entrega'",
    ).get();
    if (tablas.isEmpty) {
      await m.createTable(db.entrega);
    }

    final columnasAsignacion = await db.customSelect("PRAGMA table_info('asignacion')").get();
    final nombresAsignacion = columnasAsignacion.map((fila) => fila.data['name']).toSet();
    if (!nombresAsignacion.contains('entrega_id')) {
      await m.addColumn(db.asignacion, db.asignacion.entregaId);
    }

    await db.into(db.codigoSecuencia).insertOnConflictUpdate(
          CodigoSecuenciaCompanion.insert(entityType: 'entrega', prefijo: 'ENT', digitos: 6),
        );

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 60: foreign_key_check reportó '
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
        'Migración a schemaVersion 60: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
