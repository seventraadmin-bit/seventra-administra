import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva de la Etapa 5D (`schemaVersion` 20 → 21): agrega
/// `codigoPostalFiscal` (nullable) a `Empleado` — el CP de la Constancia
/// de Situación Fiscal, independiente del CP del domicilio.
///
/// **Aplica a `from == 18 || from == 19 || from == 20` — nunca `from <=
/// 17`.** Extiende el mismo gotcha de rango ya documentado en
/// `migrar_empleado_v20.dart` (que solo cubría `from == 18 || from ==
/// 19`): cualquier origen `from <= 17` ya crea `empleado` vía
/// `m.createTable(empleado)` (bloque `to >= 18` en `app_database.dart`)
/// con la forma *actual* de la clase Dart, que YA incluye esta columna.
/// `from == 20` es nuevo en este rango porque `migrarEmpleadoV20` ya
/// creó `empleado` con su forma concreta de esa versión (sin esta
/// columna, que nace apenas ahora) — el mismo patrón seguirá creciendo
/// cada vez que se agregue una columna a `Empleado`: el límite inferior
/// del rango es siempre 18 (la primera versión con `m.createTable`
/// literal), el superior siempre "la versión anterior a la actual".
Future<void> migrarEmpleadoV21(AppDatabase db, Migrator m, int from) async {
  await db.transaction(() async {
    if (from == 18 || from == 19 || from == 20) {
      await m.addColumn(db.empleado, db.empleado.codigoPostalFiscal);
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración de Empleado a schemaVersion 21: foreign_key_check reportó '
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
        'Migración de Empleado a schemaVersion 21: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
