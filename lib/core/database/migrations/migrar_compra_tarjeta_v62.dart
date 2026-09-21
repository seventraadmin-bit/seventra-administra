import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva (Etapa 19B, "Compra ↔ Tarjeta de crédito ↔
/// Deuda"): agrega `MovimientoDeuda.compraId` (vínculo determinista
/// hacia la Compra que originó un cargo de tarjeta — nunca inferido por
/// monto/fecha/texto) y `Compra.deudaId` (qué tarjeta financió la
/// compra). Ambas columnas nuevas, nullable, sin backfill: ninguna
/// `Compra`/`MovimientoDeuda` ya existente tiene qué reconstruir — toda
/// Compra registrada antes de esta etapa fue pagada de contado
/// (`egresoId` poblado, `deudaId` permanece `null`) y ningún
/// `MovimientoDeuda` anterior es de tipo `cargoCompra` (ese tipo no
/// existía hasta ahora — ver el doc comment de `TipoMovimientoDeuda`).
Future<void> migrarCompraTarjetaV62(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final columnasMovimientoDeuda = await db.customSelect("PRAGMA table_info('movimiento_deuda')").get();
    final nombresMovimientoDeuda = columnasMovimientoDeuda.map((fila) => fila.data['name']).toSet();
    if (!nombresMovimientoDeuda.contains('compra_id')) {
      await m.addColumn(db.movimientoDeuda, db.movimientoDeuda.compraId);
    }

    final columnasCompra = await db.customSelect("PRAGMA table_info('compra')").get();
    final nombresCompra = columnasCompra.map((fila) => fila.data['name']).toSet();
    if (!nombresCompra.contains('deuda_id')) {
      await m.addColumn(db.compra, db.compra.deudaId);
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 62: foreign_key_check reportó '
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
        'Migración a schemaVersion 62: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
