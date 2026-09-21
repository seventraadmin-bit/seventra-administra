import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva (Etapa "Origen financiero unificado — TiempoExtra,
/// Egresos manuales, TDC"): agrega 6 columnas nullable, ninguna con
/// `CHECK`/`UNIQUE` — solo `Migrator.addColumn`, sin recrear ninguna
/// tabla (mismo patrón que `migrar_deuda_ciclo_cubierto_v68.dart`).
///
/// - `movimiento_deuda.tiempo_extra_id` / `costo_adicional_id`: origen
///   estructurado de un cargo a tarjeta cuando lo origina un Tiempo
///   Extra (pago base o un costo adicional específico), mismo criterio
///   que `compra_id` ya existente.
/// - `tiempo_extra.deuda_id`: cuando el pago base de la cobertura se
///   carga directo a una tarjeta en vez de salir de una
///   CuentaFinanciera (mismo patrón dual que `Compra.egresoId`/
///   `Compra.deudaId`).
/// - `tiempo_extra_costo_adicional.forma_pago` / `egreso_id` /
///   `deuda_id`: cada costo adicional gana su PROPIO origen financiero
///   independiente — antes no existía ningún campo de origen en esta
///   tabla.
///
/// Sin backfill: toda fila existente de `TiempoExtra`/
/// `TiempoExtraCostoAdicional` queda con estos campos en `null` —
/// nunca se asume que un gasto histórico salió de una cuenta en
/// particular (el `Egreso` ya vinculado de un `TiempoExtra` existente
/// se conserva exactamente como está, vía su `egreso_id` de siempre,
/// sin tocar).
Future<void> migrarOrigenFinancieroTiempoExtraV69(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final columnasMovimiento = await db.customSelect("PRAGMA table_info('movimiento_deuda')").get();
    final nombresMovimiento = columnasMovimiento.map((fila) => fila.data['name']).toSet();
    if (!nombresMovimiento.contains('tiempo_extra_id')) {
      await m.addColumn(db.movimientoDeuda, db.movimientoDeuda.tiempoExtraId);
    }
    if (!nombresMovimiento.contains('costo_adicional_id')) {
      await m.addColumn(db.movimientoDeuda, db.movimientoDeuda.costoAdicionalId);
    }

    final columnasTiempoExtra = await db.customSelect("PRAGMA table_info('tiempo_extra')").get();
    final nombresTiempoExtra = columnasTiempoExtra.map((fila) => fila.data['name']).toSet();
    if (!nombresTiempoExtra.contains('deuda_id')) {
      await m.addColumn(db.tiempoExtra, db.tiempoExtra.deudaId);
    }

    final columnasCosto = await db.customSelect("PRAGMA table_info('tiempo_extra_costo_adicional')").get();
    final nombresCosto = columnasCosto.map((fila) => fila.data['name']).toSet();
    if (!nombresCosto.contains('forma_pago')) {
      await m.addColumn(db.tiempoExtraCostoAdicional, db.tiempoExtraCostoAdicional.formaPago);
    }
    if (!nombresCosto.contains('egreso_id')) {
      await m.addColumn(db.tiempoExtraCostoAdicional, db.tiempoExtraCostoAdicional.egresoId);
    }
    if (!nombresCosto.contains('deuda_id')) {
      await m.addColumn(db.tiempoExtraCostoAdicional, db.tiempoExtraCostoAdicional.deudaId);
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 69: foreign_key_check reportó '
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
        'Migración a schemaVersion 69: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
