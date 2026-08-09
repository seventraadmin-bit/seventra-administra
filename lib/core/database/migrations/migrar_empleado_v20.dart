import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva de la Etapa 5C (`schemaVersion` 19 → 20): crea
/// `EmpleadoPeriodoLaboral` (historial de periodos ya cerrados, nunca
/// contiene el periodo vigente — ver su doc comment) y agrega las 3
/// columnas nullable de baja del periodo laboral vigente (`fechaBaja`,
/// `motivoBaja`, `observacionesBaja`) a `Empleado`.
///
/// **La creación de la tabla aplica a cualquier `from <= 19`** — es una
/// tabla enteramente nueva, ningún origen anterior pudo haberla creado
/// ya, así que no hace falta acotar un origen exacto (mismo criterio
/// que `EntidadFiscal` en la Etapa 4E.2 o `TipoModalidadTurno`/
/// `ServicioLineaComercial` en la Etapa 4G.1).
///
/// **Las columnas nuevas de `Empleado` sí necesitan el gotcha exacto de
/// siempre, pero en su variante de rango: `from == 18 || from == 19`,
/// nunca `from <= 17`.** Motivo: `from <= 17` ya crea `empleado` vía
/// `m.createTable(empleado)` (bloque `to >= 18` en `app_database.dart`)
/// con la forma *actual* de la clase Dart, que YA incluye estas 3
/// columnas. En cambio `from == 18` (creó `empleado` en su forma de la
/// Etapa 5A, sin las columnas de 5B ni 5C) y `from == 19` (ya tiene las
/// columnas de 5B vía `migrarEmpleadoV19`, pero no las de 5C) SÍ
/// necesitan que se agreguen aquí explícitamente — agregarlas para
/// cualquier otro origen lanzaría "duplicate column name".
Future<void> migrarEmpleadoV20(AppDatabase db, Migrator m, int from) async {
  await db.transaction(() async {
    await m.createTable(db.empleadoPeriodoLaboral);

    if (from == 18 || from == 19) {
      await m.addColumn(db.empleado, db.empleado.fechaBaja);
      await m.addColumn(db.empleado, db.empleado.motivoBaja);
      await m.addColumn(db.empleado, db.empleado.observacionesBaja);
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración de Empleado a schemaVersion 20: foreign_key_check reportó '
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
        'Migración de Empleado a schemaVersion 20: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
