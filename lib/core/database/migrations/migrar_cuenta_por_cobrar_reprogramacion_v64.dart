import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva (Etapa 19D, "Calendario financiero y planeación
/// de liquidez"): agrega `CuentaPorCobrar.fechaCobroReprogramada`
/// (nullable) — nunca toca `fechaVencimiento` (la fecha contractual
/// original permanece intacta y siempre visible). Sin backfill: toda
/// CxC existente queda con `fechaCobroReprogramada: null`, mismo
/// criterio que el resto de las columnas nullable agregadas en este
/// proyecto.
Future<void> migrarCuentaPorCobrarReprogramacionV64(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final columnas = await db.customSelect("PRAGMA table_info('cuenta_por_cobrar')").get();
    final nombres = columnas.map((fila) => fila.data['name']).toSet();
    if (!nombres.contains('fecha_cobro_reprogramada')) {
      await m.addColumn(db.cuentaPorCobrar, db.cuentaPorCobrar.fechaCobroReprogramada);
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 64: foreign_key_check reportó '
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
        'Migración a schemaVersion 64: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
