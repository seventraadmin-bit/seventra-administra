import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva de la Etapa 9A (`schemaVersion` 33 → 34): funda el
/// dominio Telefonía — crea `LineaTelefonica` junto con el índice único
/// parcial de `LineaTelefonica.numero`
/// (`idx_linea_telefonica_numero_unico`), que refuerza a nivel de BD
/// "número único cuando se captura" — mismo criterio y mismo mecanismo
/// que `migrarVehiculoV30` (Etapa 8A).
///
/// Originalmente también creaba `LineaTelefonicaPlan` — retirada por
/// completo en la Etapa 9C al confirmarse que la operación real de
/// Telefonía es prepago, nunca planes/contratos (ver
/// `migrarRecargaLineaTelefonicaV36`, que la elimina con `DROP TABLE
/// IF EXISTS`). Este paso ya **no** la crea: cualquier instalación que
/// salte de una versión ≤33 directo a la actual jamás necesita
/// materializarla, porque el paso 36 la eliminaría en el mismo salto de
/// todos modos — crearla solo para borrarla momentos después no aporta
/// nada. Una instalación que ya esté exactamente en 34/35 (con la tabla
/// real, aunque siempre vacía en la práctica) la pierde igual vía el
/// `DROP TABLE IF EXISTS` del paso 36, sin pasar por aquí.
///
/// Tabla enteramente nueva — ningún origen anterior pudo haberla creado
/// ya, así que `to >= 34 && from <= 33` es seguro sin acotar un origen
/// exacto.
///
/// `Migrator.createTable` **no** crea automáticamente los índices
/// declarados vía `@TableIndex.sql` — hace falta `m.createIndex(...)`
/// explícito.
Future<void> migrarLineaTelefonicaV34(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    await m.createTable(db.lineaTelefonica);
    await m.createIndex(db.idxLineaTelefonicaNumeroUnico);

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
