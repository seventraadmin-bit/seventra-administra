import 'package:drift/drift.dart';

import '../app_database.dart';

/// Fragmentación de `usuarios.administrar` (Etapa "Usuarios, permisos y
/// UX de seguridad").
///
/// Hasta esta etapa UN SOLO permiso cubría toda la Configuración
/// no-Maestro: crear usuarios, editarlos, resetear su contraseña,
/// activarlos/desactivarlos, otorgarles permisos Y consultar la
/// auditoría del sistema. Son responsabilidades de sensibilidad muy
/// distinta — sobre todo "otorgar permisos", que es la facultad con la
/// que un usuario podría ampliarse el alcance a sí mismo o a otros.
///
/// `usuarios.administrar` CONSERVA su código (sigue cubriendo el alta y
/// la edición de cuentas, y sigue siendo el permiso que gatea la ruta
/// `/configuracion`), y se le separan dos facultades nuevas más un
/// permiso de solo lectura para Auditoría.
///
/// Regla de migración (idéntica y conservadora, mismo criterio que
/// `migrar_permisos_granulares_v71.dart`): todo usuario que ya tenía
/// `usuarios.administrar` recibe los códigos nuevos equivalentes a lo
/// que ese código YA le permitía hacer — nunca se le quita nada, y
/// nunca se le otorga una facultad que antes no tuviera. Aquí los tres
/// códigos nuevos son literalmente cosas que `usuarios.administrar` ya
/// autorizaba, así que la equivalencia histórica es demostrable.
///
/// El Usuario Maestro nunca tiene filas en `PermisoUsuario` (su acceso
/// se recalcula en vivo), así que esta migración no lo toca.
///
/// Idempotente: cada inserción se verifica antes; correrla dos veces no
/// duplica ninguna fila ni viola la llave primaria `(usuarioId, codigo)`.
const migracionPermisosUsuariosV78 = <String, List<String>>{
  'usuarios.administrar': [
    // Otorgar/quitar permisos a otras cuentas — la facultad más
    // sensible del módulo, ahora separable de "editar una cuenta".
    'usuarios.otorgarPermisos',
    // Resetear la contraseña de otra persona (deja la cuenta con
    // contraseña temporal y cambio obligatorio).
    'usuarios.resetearPassword',
    // Consultar la auditoría del sistema. Es SOLO LECTURA: el historial
    // es append-only desde la UI, no existe ninguna acción que lo
    // modifique o borre.
    'auditoria.ver',
  ],
};

/// Migración aditiva + de datos (schemaVersion 78):
///
/// - `usuario.empleado_id` (nullable, `restrict`): vincula la cuenta al
///   expediente de Personal, para que nombre/puesto dejen de ser una
///   segunda identidad que puede divergir. **Sin backfill**: emparejar
///   cuentas con empleados por nombre sería adivinar, y este proyecto no
///   adivina. Las cuentas existentes quedan en `null` y siguen usando su
///   `nombre`/`puesto_id` propios exactamente como hasta hoy.
/// - `usuario.debe_cambiar_password` (default `false`): cambio
///   obligatorio en el primer acceso para cuentas creadas por un
///   Maestro. `false` en todas las existentes — nadie que ya usaba el
///   sistema se ve obligado a cambiar nada.
/// - Fragmentación de permisos descrita arriba.
Future<void> migrarUsuariosPermisosV78(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final columnas = await db.customSelect("PRAGMA table_info('usuario')").get();
    final nombres = columnas.map((fila) => fila.data['name']).toSet();

    if (!nombres.contains('empleado_id')) {
      await m.addColumn(db.usuario, db.usuario.empleadoId);
    }
    if (!nombres.contains('debe_cambiar_password')) {
      await m.addColumn(db.usuario, db.usuario.debeCambiarPassword);
    }

    for (final entrada in migracionPermisosUsuariosV78.entries) {
      final usuariosConCodigoViejo =
          await (db.select(db.permisoUsuario)..where((t) => t.codigo.equals(entrada.key))).get();

      for (final fila in usuariosConCodigoViejo) {
        for (final codigoNuevo in entrada.value) {
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
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 78: foreign_key_check reportó '
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
        'Migración a schemaVersion 78: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
