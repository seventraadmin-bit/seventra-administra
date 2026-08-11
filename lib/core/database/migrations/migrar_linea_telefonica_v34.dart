import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva de la Etapa 9A (`schemaVersion` 33 → 34): funda el
/// dominio Telefonía — crea `LineaTelefonica`/`LineaTelefonicaPlan`
/// junto con el índice único parcial de `LineaTelefonica.numero`
/// (`idx_linea_telefonica_numero_unico`), que refuerza a nivel de BD
/// "número único cuando se captura" — mismo criterio y mismo mecanismo
/// que `migrarVehiculoV30` (Etapa 8A).
///
/// Tablas enteramente nuevas — ningún origen anterior pudo haberlas
/// creado ya, así que `to >= 34 && from <= 33` es seguro sin acotar un
/// origen exacto.
///
/// `Migrator.createTable` **no** crea automáticamente los índices
/// declarados vía `@TableIndex.sql` — hace falta `m.createIndex(...)`
/// explícito.
Future<void> migrarLineaTelefonicaV34(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    await m.createTable(db.lineaTelefonica);
    await m.createIndex(db.idxLineaTelefonicaNumeroUnico);
    await m.createTable(db.lineaTelefonicaPlan);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 34: foreign_key_check reportó '
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
        'Migración a schemaVersion 34: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
