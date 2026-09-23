import 'package:drift/drift.dart';

import '../app_database.dart';

/// schemaVersion 92 — Etapa 3B, identidad híbrida `Usuario` ↔ `Empleado`.
///
/// **Puramente aditiva, y sin una sola escritura de datos.** No crea
/// tablas, no agrega columnas, no rellena nada y no reescribe ningún
/// evento. Lo único que hace es crear el índice único parcial que
/// garantiza "un Empleado, como máximo una cuenta".
///
/// Por qué un índice parcial y no un `UNIQUE` de columna:
///  1. `UNIQUE` en la definición de la columna obliga a **recrear la
///     tabla** (el autoindex que genera sólo se quita recreándola —
///     lección cara de la v79), y `usuario` es referenciada por
///     `permiso_usuario`, `usuario_evento`, `sesion_persistente` y por
///     el `actor_usuario_id` de una quincena de tablas de eventos.
///     Recrearla para esto sería un riesgo desproporcionado.
///  2. Un índice se crea con `IF NOT EXISTS` y es idempotente.
///  3. `WHERE empleado_id IS NOT NULL` deja explícito lo que SQLite ya
///     hace por su cuenta: varios NULL nunca chocan entre sí. Una
///     cuenta independiente (Maestro del bootstrap, administrador sin
///     expediente) sigue siendo legal, y pueden coexistir tantas como
///     haga falta.
///
/// **No se vincula ninguna cuenta automáticamente.** Emparejar por
/// nombre, por nombre de usuario o por puesto sería exactamente la
/// adivinanza que este proyecto no hace: una cuenta declara a quién
/// pertenece porque alguien lo decidió, nunca porque dos cadenas se
/// parecían. Las cuentas existentes siguen con `empleado_id` nulo hasta
/// que un administrador las vincule a mano.
///
/// Mismo molde de verificación que v80/v87..v91.
Future<void> migrarVinculoUsuarioEmpleadoV92(AppDatabase db, Migrator m) async {
  // La unicidad se comprueba ANTES de crear el índice: si una base
  // real tuviera ya dos cuentas apuntando al mismo Empleado, crear el
  // índice fallaría con un error de SQLite ilegible. Preferimos fallar
  // aquí, diciendo exactamente cuál es el problema, y NUNCA "repararlo"
  // por nuestra cuenta: decidir cuál de las dos cuentas conserva a la
  // persona es una decisión de negocio, no de una migración.
  final duplicados = await db.customSelect('''
    SELECT empleado_id, COUNT(*) AS n
    FROM usuario
    WHERE empleado_id IS NOT NULL
    GROUP BY empleado_id
    HAVING n > 1
  ''').get();
  if (duplicados.isNotEmpty) {
    throw StateError(
      'migrarVinculoUsuarioEmpleadoV92: ${duplicados.length} Empleado(s) tienen más de una '
      'cuenta de Usuario. Resuelve manualmente cuál conserva el vínculo antes de migrar.',
    );
  }

  // `Migrator.createTable` no emite los índices declarados con
  // `@TableIndex.sql` (gotcha conocido desde la v30), y aquí ni
  // siquiera se crea la tabla: el índice va explícito.
  await db.customStatement(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_usuario_empleado_unico '
    'ON usuario (empleado_id) WHERE empleado_id IS NOT NULL',
  );

  final fk = await db.customSelect('PRAGMA foreign_key_check').get();
  if (fk.isNotEmpty) {
    throw StateError('migrarVinculoUsuarioEmpleadoV92: PRAGMA foreign_key_check reportó ${fk.length} problema(s).');
  }
  final integridad = await db.customSelect('PRAGMA integrity_check').getSingle();
  final resultado = integridad.data.values.first;
  if (resultado != 'ok') {
    throw StateError('migrarVinculoUsuarioEmpleadoV92: PRAGMA integrity_check devolvió "$resultado".');
  }
}
