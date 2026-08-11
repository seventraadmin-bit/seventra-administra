import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración de la Etapa 11A (`schemaVersion` 37 → 38): funda el dominio
/// Usuarios — `Usuario` (cuenta de acceso, sin FK a `Empleado` a
/// propósito) y `UsuarioEvento` (historial administrativo append-only).
/// `PermisoUsuario` llega en la Etapa 11B, no aquí — 11A todavía no
/// otorga ni exige ningún permiso.
///
/// Tablas enteramente nuevas — ningún origen anterior pudo haberlas
/// creado ya, así que `from <= 37` es seguro sin acotar un origen
/// exacto. Sin seed de `CodigoSecuencia`: `Usuario` no tiene folio, su
/// identificador humano es `nombreUsuario`.
Future<void> migrarUsuarioV38(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    await m.createTable(db.usuario);
    await m.createTable(db.usuarioEvento);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 38: foreign_key_check reportó '
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
        'Migración a schemaVersion 38: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
