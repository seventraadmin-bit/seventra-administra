import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración de la Etapa 10 (`schemaVersion` 36 → 37): funda el dominio
/// Compras — `Compra`, `CompraPartida`, `CompraPartidaMovimiento`
/// (origen navegable hacia Inventario), `CompraAttachment` (comprobante
/// opcional) y `CompraEvento`. No toca `movimiento_inventario`,
/// `articulo_unidad` ni `egreso` — la integración con Inventario/
/// Finanzas se compone en tiempo de ejecución vía sus repositorios
/// reales (`InventarioRepository`/`EgresoRepository`), nunca vía cambio
/// de esquema en esos dominios.
///
/// Tablas enteramente nuevas — ningún origen anterior pudo haberlas
/// creado ya, así que `from <= 36` es seguro sin acotar un origen
/// exacto. El contador de código `'compra'` se siembra vía `runSeed()`
/// normal (agregado a `_seedCodigoSecuencia` en `seed_data.dart`), no
/// aquí.
Future<void> migrarCompraV37(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    await m.createTable(db.compra);
    await m.createTable(db.compraPartida);
    await m.createTable(db.compraPartidaMovimiento);
    await m.createTable(db.compraAttachment);
    await m.createTable(db.compraEvento);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 37: foreign_key_check reportó '
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
        'Migración a schemaVersion 37: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
