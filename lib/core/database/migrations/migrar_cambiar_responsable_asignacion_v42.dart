import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración de la Etapa 9D, ajuste posterior a la aprobación inicial
/// (`schemaVersion` 41 → 42): agrega `Asignacion.actorUsuarioId`.
///
/// `Asignacion` nunca quedó entre las 15 tablas de la Etapa 11D — esas
/// eran tablas de evento/ledger, `Asignacion` es de estado vigente. Se
/// agrega ahora porque la nueva operación `cambiarResponsable` (cambiar
/// quién es responsable del mismo bien, sin generar `MovimientoInventario`)
/// no tiene ningún otro lugar donde registrar el actor — y de paso se
/// completa también en `crear`/`cerrar`/`reemplazar`, que antes solo
/// dejaban el actor en el `MovimientoInventario` asociado, nunca en la
/// propia fila de `Asignacion`.
///
/// Puramente aditiva.
///
/// **Mismo gotcha que `migrar_auditoria_v40.dart`/`migrar_equipos_telefonicos_v41.dart`**
/// (hallado de nuevo al validar contra `schemaAt(1)`): `Asignacion`
/// existe desde la Etapa 7B, pero su `createTable` original (dentro de
/// su propia migración histórica) siempre lee la forma *actual* de la
/// clase Dart — que ya incluye `actorUsuarioId`. Una instalación que
/// llega desde un origen anterior a la creación de `Asignacion` recibe
/// la columna gratis por ese `createTable`; `addColumn` sin condición
/// falla con "duplicate column name" en ese caso. Se usa el mismo
/// chequeo `PRAGMA table_info` que las dos migraciones anteriores.
Future<void> migrarCambiarResponsableAsignacionV42(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final columnas = await db.customSelect("PRAGMA table_info('asignacion')").get();
    final yaExiste = columnas.any((fila) => fila.data['name'] == 'actor_usuario_id');
    if (!yaExiste) {
      await m.addColumn(db.asignacion, db.asignacion.actorUsuarioId);
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 42: foreign_key_check reportó '
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
        'Migración a schemaVersion 42: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
