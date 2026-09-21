import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva (Etapa 19C, "Posición de caja, flujo real y
/// proyección de compromisos"): tabla nueva `CuentaFinanciera`
/// (Banco/Efectivo, sin `saldoActual` persistido — siempre derivado de
/// sus movimientos) + `Ingreso.cuentaFinancieraId`/
/// `Egreso.cuentaFinancieraId` (ambas nullable, `restrict`) + fila
/// nueva de `CodigoSecuencia` (`cuenta_financiera` → `CTA`). Ninguna
/// tabla/columna existente se modifica ni se elimina; sin backfill —
/// todo Ingreso/Egreso histórico queda con `cuentaFinancieraId: null`
/// ("Cuenta no especificada"), nunca inferido de `cuentaCaja` (texto
/// libre, sin tocar).
Future<void> migrarCuentaFinancieraV63(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final tablaCuentaFinanciera = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='table' AND name = 'cuenta_financiera'")
        .get();
    if (tablaCuentaFinanciera.isEmpty) {
      await m.createTable(db.cuentaFinanciera);
    }

    final columnasIngreso = await db.customSelect("PRAGMA table_info('ingreso')").get();
    final nombresIngreso = columnasIngreso.map((fila) => fila.data['name']).toSet();
    if (!nombresIngreso.contains('cuenta_financiera_id')) {
      await m.addColumn(db.ingreso, db.ingreso.cuentaFinancieraId);
    }

    final columnasEgreso = await db.customSelect("PRAGMA table_info('egreso')").get();
    final nombresEgreso = columnasEgreso.map((fila) => fila.data['name']).toSet();
    if (!nombresEgreso.contains('cuenta_financiera_id')) {
      await m.addColumn(db.egreso, db.egreso.cuentaFinancieraId);
    }

    await db.into(db.codigoSecuencia).insertOnConflictUpdate(
          CodigoSecuenciaCompanion.insert(entityType: 'cuenta_financiera', prefijo: 'CTA', digitos: 4),
        );

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 63: foreign_key_check reportó '
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
        'Migración a schemaVersion 63: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
