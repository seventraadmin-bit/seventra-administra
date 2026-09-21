import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva (Etapa "Dashboard: posición financiera + ciclo de
/// TDC"): agrega una sola columna nullable, `tarjetaVencimientoCubiertoHasta`,
/// a `Deuda`. Sin `CHECK`, así que — mismo patrón que
/// `migrarDeudaTasaCatV67` — solo `Migrator.addColumn`, nunca recrea la
/// tabla.
///
/// Sin backfill: toda Deuda existente queda con el campo en `null`, que
/// por diseño reproduce EXACTAMENTE el comportamiento de siempre en
/// `proximaFechaLimitePago` (próxima ocurrencia >= hoy, nunca "vencida")
/// — ninguna tarjeta existente cambia su comportamiento visible hasta
/// que alguien la concilie explícitamente o registre un pago real. Ver
/// el doc comment del campo en `deuda_table.dart`.
Future<void> migrarDeudaCicloCubiertoV68(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final columnas = await db.customSelect("PRAGMA table_info('deuda')").get();
    final nombres = columnas.map((fila) => fila.data['name']).toSet();

    if (!nombres.contains('tarjeta_vencimiento_cubierto_hasta')) {
      await m.addColumn(db.deuda, db.deuda.tarjetaVencimientoCubiertoHasta);
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración de Deuda a schemaVersion 68: foreign_key_check reportó '
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
        'Migración de Deuda a schemaVersion 68: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
