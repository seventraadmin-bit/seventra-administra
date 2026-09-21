import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración de la Etapa 7 ("Cuentas por cobrar — corrección,
/// cancelación, trazabilidad y consistencia con Agenda/Pagos"):
/// puramente de datos, sin cambio de esquema — `PermisoUsuario.codigo`
/// es texto libre (mismo criterio que `migrarPermisosGranularesV71`).
///
/// `cuentaPorCobrar.corregirFecha` evoluciona a `cuentaPorCobrar.corregir`
/// (más amplio: ahora también cubre `observaciones`, no solo
/// `fechaVencimiento`) — cada usuario que ya tenía `corregirFecha`
/// recibe `corregir`, nunca se le quita nada (el código viejo se
/// conserva tal cual en `PermisoUsuario`, fila inerte). `cuentaPorCobrar.
/// reprogramarCobro` no cambia. `cuentaPorCobrar.cancelar` es nuevo —
/// nunca se otorga retroactivamente (nadie lo tenía antes de que
/// existiera).
///
/// Idempotente: cada inserción se verifica antes (`getSingleOrNull`),
/// correrla dos veces no duplica ninguna fila ni falla por violar la
/// llave primaria `(usuarioId, codigo)`. El Usuario Maestro nunca tiene
/// filas de `PermisoUsuario` (su acceso se recalcula en vivo), así que
/// esta migración no lo toca ni necesita tocarlo.
Future<void> migrarCorreccionCuentaPorCobrarV74(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final usuariosConCodigoViejo =
        await (db.select(db.permisoUsuario)..where((t) => t.codigo.equals('cuentaPorCobrar.corregirFecha'))).get();

    for (final fila in usuariosConCodigoViejo) {
      final yaExiste = await (db.select(db.permisoUsuario)
            ..where((t) => t.usuarioId.equals(fila.usuarioId) & t.codigo.equals('cuentaPorCobrar.corregir')))
          .getSingleOrNull();
      if (yaExiste == null) {
        await db.into(db.permisoUsuario).insert(
              PermisoUsuarioCompanion.insert(usuarioId: fila.usuarioId, codigo: 'cuentaPorCobrar.corregir'),
            );
      }
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 74: foreign_key_check reportó '
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
        'Migración a schemaVersion 74: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
