import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva (Etapa "Origen financiero de Egresos manuales:
/// Cuenta vs. TDC"): agrega 2 columnas nullable, ninguna con
/// `CHECK`/`UNIQUE` — solo `Migrator.addColumn`, sin recrear ninguna
/// tabla (mismo patrón exacto que
/// `migrar_origen_financiero_tiempo_extra_v69.dart`).
///
/// - `egreso.deuda_id`: la tarjeta de crédito que financió un gasto
///   manual, cuando NO salió dinero de ninguna `CuentaFinanciera`.
///   Mutuamente excluyente con `cuenta_financiera_id` — ver el doc
///   comment de la columna en `egreso_table.dart`.
/// - `movimiento_deuda.egreso_gasto_id`: el `Egreso` que ORIGINÓ un
///   cargo a tarjeta — cuarto miembro del grupo `compra_id`/
///   `tiempo_extra_id`/`costo_adicional_id`. Distinta de `egreso_id`
///   (que es el Egreso GENERADO por un pago, dirección contraria).
///
/// **Sin backfill, deliberadamente.** La instalación real tiene hoy 5
/// Egresos con `forma_pago == 'tarjeta'` (auditoría contra la BD real
/// de la Etapa): 2 sin cuenta financiera y 3 con una asignada. Ninguno
/// guarda en ninguna parte CUÁL tarjeta lo financió — `forma_pago` es
/// una etiqueta descriptiva sin FK, y adivinar la TDC por
/// concepto/monto/fecha sería exactamente la heurística que este
/// proyecto nunca aplica. Esas filas conservan su estado tal cual
/// (incluido su efecto actual sobre Caja y bancos, correcto o no) y
/// deben corregirse a mano desde "Corregir egreso", que a partir de
/// esta etapa ya ofrece la TDC como origen real.
Future<void> migrarEgresoOrigenTarjetaV76(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final columnasEgreso = await db.customSelect("PRAGMA table_info('egreso')").get();
    final nombresEgreso = columnasEgreso.map((fila) => fila.data['name']).toSet();
    if (!nombresEgreso.contains('deuda_id')) {
      await m.addColumn(db.egreso, db.egreso.deudaId);
    }

    final columnasMovimiento = await db.customSelect("PRAGMA table_info('movimiento_deuda')").get();
    final nombresMovimiento = columnasMovimiento.map((fila) => fila.data['name']).toSet();
    if (!nombresMovimiento.contains('egreso_gasto_id')) {
      await m.addColumn(db.movimientoDeuda, db.movimientoDeuda.egresoGastoId);
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 76: foreign_key_check reportó '
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
        'Migración a schemaVersion 76: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
