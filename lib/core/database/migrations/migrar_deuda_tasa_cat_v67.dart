import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva (Etapa "Tasa fija/variable y CAT para TDC", caso
/// real Konfío Empresarial): agrega 7 columnas nullable a `Deuda` —
/// `tarjetaTipoTasa`, `tarjetaTasaReferencia`, `tarjetaTasaDiferencial`,
/// `tarjetaTasaMasIva`, `tarjetaTasaDescripcion`, `tarjetaCat`,
/// `tarjetaCatIncluyeIva`. Ninguna lleva `CHECK` — a diferencia de
/// `migrarDeudaTarjetaRevolventeV66`, esta migración NO recrea la
/// tabla, solo `Migrator.addColumn` (mismo patrón que
/// `migrarCuentaPorCobrarReprogramacionV64`).
///
/// `tasaInteres` (ya existente) NUNCA se toca — sigue siendo la tasa
/// anual simple de una deuda fija, y pasa a significar específicamente
/// "tasa fija anual" para una TDC cuando `tarjetaTipoTasa == fija`.
///
/// Backfill fiel (nunca inventa nada): toda TDC que YA tenía
/// `tasaInteres` capturado bajo el formulario anterior solo podía
/// significar una tasa fija (esa era la única interpretación que ese
/// formulario permitía) — se marca `tarjetaTipoTasa = 'fija'` para
/// hacer explícito lo que ya era cierto implícitamente, mismo criterio
/// que el backfill de `tarjetaReglaFechaPago` en la migración v66.
/// Préstamo/financiamiento/otro nunca reciben este backfill (el campo
/// es exclusivo de tarjeta) ni pierden su propio `tasaInteres`.
Future<void> migrarDeudaTasaCatV67(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final columnas = await db.customSelect("PRAGMA table_info('deuda')").get();
    final nombres = columnas.map((fila) => fila.data['name']).toSet();

    if (!nombres.contains('tarjeta_tipo_tasa')) {
      await m.addColumn(db.deuda, db.deuda.tarjetaTipoTasa);
    }
    if (!nombres.contains('tarjeta_tasa_referencia')) {
      await m.addColumn(db.deuda, db.deuda.tarjetaTasaReferencia);
    }
    if (!nombres.contains('tarjeta_tasa_diferencial')) {
      await m.addColumn(db.deuda, db.deuda.tarjetaTasaDiferencial);
    }
    if (!nombres.contains('tarjeta_tasa_mas_iva')) {
      await m.addColumn(db.deuda, db.deuda.tarjetaTasaMasIva);
    }
    if (!nombres.contains('tarjeta_tasa_descripcion')) {
      await m.addColumn(db.deuda, db.deuda.tarjetaTasaDescripcion);
    }
    if (!nombres.contains('tarjeta_cat')) {
      await m.addColumn(db.deuda, db.deuda.tarjetaCat);
    }
    if (!nombres.contains('tarjeta_cat_incluye_iva')) {
      await m.addColumn(db.deuda, db.deuda.tarjetaCatIncluyeIva);
    }

    await db.customStatement('''
      UPDATE deuda
      SET tarjeta_tipo_tasa = 'fija'
      WHERE tipo = 'tarjetaCredito' AND tasa_interes IS NOT NULL
    ''');

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración de Deuda a schemaVersion 67: foreign_key_check reportó '
        '${violacionesFk.length} violación(es). Migración abortada.',
      );
    }

    final resultadoIntegridad = await db
        .customSelect('PRAGMA integrity_check')
        .map((r) => r.data['integrity_check'] as String)
        .get();
    final integridadOk = resultadoIntegridad.length == 1 && resultadoIntegridad.single == 'ok';
    if (!integridadOk) {
      throw StateError(
        'Migración de Deuda a schemaVersion 67: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
