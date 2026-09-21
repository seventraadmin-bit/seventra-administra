import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración de la Etapa "corrección real de Tiempo Extra":
///
/// 1. Aditiva — `tiempo_extra_evento.estado_anterior`/`estado_nuevo`
///    (`TEXT` nullable, sin `CHECK`/`UNIQUE`, solo `Migrator.addColumn`)
///    para el nuevo tipo de evento `corregido`. Filas `registrado`/
///    `cancelado` existentes quedan con ambos campos en `null` — nunca
///    se rellenan retroactivamente. También
///    `tiempo_extra_costo_adicional.eliminado` (`BOOLEAN NOT NULL
///    DEFAULT FALSE`, sin `CHECK`/`UNIQUE` propios más allá del default
///    — soportado por `ALTER TABLE ADD COLUMN`) — borrado lógico de un
///    costo adicional "quitado" durante una corrección (ver el doc
///    comment de la columna en `tiempo_extra_table.dart`). Filas
///    existentes quedan `false` (ningún costo histórico estaba
///    "eliminado").
/// 2. De datos, sin cambio de esquema — el permiso único
///    `personal.gestionarTiemposExtra` se reemplaza por 3 permisos
///    separados (`tiempoExtra.crear`/`corregir`/`cancelar`). Sin este
///    paso, cualquier usuario que ya tuviera el código viejo perdería
///    silenciosamente el acceso al reemplazarlo en el catálogo — se le
///    otorgan los 3 nuevos (nunca `eliminarFisicamente`, que no es un
///    permiso otorgable). El código viejo se conserva tal cual en
///    `PermisoUsuario` (fila inerte, ya no aparece en el catálogo) en
///    vez de borrarse — `codigo` es texto libre, no requiere limpieza.
Future<void> migrarCorreccionTiempoExtraV70(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final columnasEvento = await db.customSelect("PRAGMA table_info('tiempo_extra_evento')").get();
    final nombresEvento = columnasEvento.map((fila) => fila.data['name']).toSet();
    if (!nombresEvento.contains('estado_anterior')) {
      await m.addColumn(db.tiempoExtraEvento, db.tiempoExtraEvento.estadoAnterior);
    }
    if (!nombresEvento.contains('estado_nuevo')) {
      await m.addColumn(db.tiempoExtraEvento, db.tiempoExtraEvento.estadoNuevo);
    }

    final columnasCosto = await db.customSelect("PRAGMA table_info('tiempo_extra_costo_adicional')").get();
    final nombresCosto = columnasCosto.map((fila) => fila.data['name']).toSet();
    if (!nombresCosto.contains('eliminado')) {
      await m.addColumn(db.tiempoExtraCostoAdicional, db.tiempoExtraCostoAdicional.eliminado);
    }

    final usuariosConPermisoViejo = await (db.select(db.permisoUsuario)
          ..where((t) => t.codigo.equals('personal.gestionarTiemposExtra')))
        .get();
    for (final fila in usuariosConPermisoViejo) {
      for (final codigoNuevo in ['tiempoExtra.crear', 'tiempoExtra.corregir', 'tiempoExtra.cancelar']) {
        final yaExiste = await (db.select(db.permisoUsuario)
              ..where((t) => t.usuarioId.equals(fila.usuarioId) & t.codigo.equals(codigoNuevo)))
            .getSingleOrNull();
        if (yaExiste == null) {
          await db.into(db.permisoUsuario).insert(
                PermisoUsuarioCompanion.insert(usuarioId: fila.usuarioId, codigo: codigoNuevo),
              );
        }
      }
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 70: foreign_key_check reportó '
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
        'Migración a schemaVersion 70: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
