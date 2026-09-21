import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva (Etapa 19, "Deudas y crédito empresarial"): dos
/// tablas enteramente nuevas — `Deuda` (identidad propia con saldo,
/// nunca una `CategoriaFinanciera` más) y `MovimientoDeuda` (historial
/// append-only con saldo explícito por línea) — más una fila nueva de
/// `CodigoSecuencia` (`deuda` → `DEU`). Ninguna tabla ni columna
/// existente se modifica ni se elimina; no requiere backfill.
Future<void> migrarDeudasCreditoV61(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final tablaDeuda = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = 'deuda'",
    ).get();
    if (tablaDeuda.isEmpty) {
      await m.createTable(db.deuda);
    }

    final tablaMovimientoDeuda = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = 'movimiento_deuda'",
    ).get();
    if (tablaMovimientoDeuda.isEmpty) {
      await m.createTable(db.movimientoDeuda);
    }

    await db.into(db.codigoSecuencia).insertOnConflictUpdate(
          CodigoSecuenciaCompanion.insert(entityType: 'deuda', prefijo: 'DEU', digitos: 6),
        );

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 61: foreign_key_check reportó '
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
        'Migración a schemaVersion 61: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
