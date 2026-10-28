import 'package:drift/drift.dart';

import '../app_database.dart';

/// Complemento de pago sustituto (schemaVersion 79).
///
/// **Causa estructural que corrige.** `ComplementoPago.pago_id` se
/// declaró `UNIQUE` a nivel de columna, expresando un 1:1 estricto con
/// `Pago`. El ciclo fiscal real no es 1:1: cancelar un Complemento
/// reactiva la obligación (`complementoPendiente` vuelve a `true`) y
/// exige registrar un sustituto — pero la fila cancelada seguía
/// ocupando el único lugar permitido, así que el sustituto se rechazaba
/// con `YaExiste` y el Pago quedaba pendiente para siempre.
///
/// **Invariante nuevo**: un Pago puede tener N Complementos históricos,
/// y a lo más UNO con `estatus = 'registrado'` al mismo tiempo. Eso es
/// un índice único PARCIAL, no una restricción de columna.
///
/// **Por qué hay que recrear la tabla.** En SQLite un `UNIQUE` de
/// columna dentro de `CREATE TABLE` genera un índice implícito
/// (`sqlite_autoindex_…`) que `DROP INDEX` **no puede eliminar**. La
/// única vía soportada es el procedimiento oficial de 12 pasos de
/// `ALTER TABLE`, que Drift expone como `Migrator.alterTable` con un
/// `TableMigration`: crea la tabla nueva con la definición Dart actual
/// (ya sin `UNIQUE`), copia todas las filas y sustituye la original.
///
/// **Preservación de datos**: `columnTransformer` va vacío a propósito
/// — ninguna columna cambia de nombre, tipo ni semántica, así que
/// Drift copia todas las filas tal cual. Ningún Complemento existente
/// se pierde, se reescribe ni cambia de `id`; sus eventos
/// (`ComplementoPagoEvento`) y adjuntos siguen apuntando a los mismos
/// `id`.
///
/// **Seguridad del índice parcial**: se crea DESPUÉS de copiar. Si los
/// datos actuales violaran el invariante (dos Complementos
/// `registrado` para un mismo Pago), la creación fallaría y toda la
/// migración se revertiría — nunca se quedaría a medias. Con el
/// `UNIQUE` previo eso es imposible por construcción: como máximo
/// existía una fila por Pago.
///
/// Idempotente: `alterTable` reconstruye desde la definición vigente y
/// el índice se crea con `IF NOT EXISTS`.
Future<void> migrarComplementoSustitutoV79(AppDatabase db, Migrator m) async {
  // 1. Reconstruye `complemento_pago` sin el UNIQUE de columna,
  //    conservando todas las filas.
  await m.alterTable(TableMigration(db.complementoPago));

  // 2. El invariante real: a lo más un Complemento VIGENTE por Pago.
  //    Las filas canceladas quedan fuera del índice y por eso pueden
  //    acumularse sin bloquear al sustituto.
  await db.customStatement(
    'CREATE UNIQUE INDEX IF NOT EXISTS complemento_pago_vigente_por_pago '
    "ON complemento_pago (pago_id) WHERE estatus = 'registrado'",
  );

  // 3. Verificación explícita, mismo criterio que las migraciones
  //    anteriores del proyecto: ninguna FK rota ni corrupción tras
  //    recrear la tabla.
  final fk = await db.customSelect('PRAGMA foreign_key_check').get();
  if (fk.isNotEmpty) {
    throw StateError('migrarComplementoSustitutoV79: foreign_key_check reportó ${fk.length} violaciones');
  }
  final integridad = await db.customSelect('PRAGMA integrity_check').getSingle();
  final resultado = integridad.data.values.first;
  if (resultado != 'ok') {
    throw StateError('migrarComplementoSustitutoV79: integrity_check devolvió "$resultado"');
  }
}
