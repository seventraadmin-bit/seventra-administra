import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva de la Etapa 5D (`schemaVersion` 20 → 21): crea
/// `AsignacionServicio` (relación Personal↔Servicio, ver su doc
/// comment) junto con su índice único parcial (`idx_asignacion_
/// servicio_empleado_activa`), que refuerza a nivel de BD "un Empleado
/// solo puede tener una asignación vigente a la vez".
///
/// Tabla enteramente nueva — ningún origen anterior pudo haberla creado
/// ya, así que `to >= 21 && from <= 20` es seguro sin acotar un origen
/// exacto (mismo criterio que `EntidadFiscal` en la Etapa 4E.2).
///
/// `Migrator.createTable` **no** crea automáticamente los índices
/// declarados vía `@TableIndex.sql` — hace falta `m.createIndex(...)`
/// explícito (mismo patrón ya usado en `migrarClienteContactoV4` para
/// `idxContactoClienteTipoPrincipalActivo`).
Future<void> migrarAsignacionServicioV21(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    await m.createTable(db.asignacionServicio);
    await m.createIndex(db.idxAsignacionServicioEmpleadoActiva);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 21: foreign_key_check reportó '
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
        'Migración a schemaVersion 21: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
