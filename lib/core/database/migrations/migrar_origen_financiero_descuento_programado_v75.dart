import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva (Etapa "Cierre del ciclo financiero de Descuentos
/// Programados — Préstamo/Botas"): agrega 2 columnas nullable a
/// `descuento_programado_empleado`, ninguna con `CHECK`/`UNIQUE` — solo
/// `Migrator.addColumn`, sin recrear la tabla (mismo patrón que
/// `migrar_origen_financiero_tiempo_extra_v69.dart`).
///
/// - `cuenta_financiera_id`/`egreso_id`: origen financiero real del
///   desembolso (típicamente un préstamo) — presentes solo cuando la
///   obligación produjo una salida de dinero real de una
///   `CuentaFinanciera`. La SEÑAL de "hubo desembolso" es la presencia
///   de estas columnas, nunca el valor de `tipo` — ver el doc comment
///   de la tabla.
///
/// Sin backfill: todo préstamo/descuento existente queda con ambos
/// campos en `null` — nunca se asume retroactivamente que un
/// desembolso histórico salió de una cuenta en particular.
Future<void> migrarOrigenFinancieroDescuentoProgramadoV75(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final columnas = await db.customSelect("PRAGMA table_info('descuento_programado_empleado')").get();
    final nombres = columnas.map((fila) => fila.data['name']).toSet();
    if (!nombres.contains('cuenta_financiera_id')) {
      await m.addColumn(db.descuentoProgramadoEmpleado, db.descuentoProgramadoEmpleado.cuentaFinancieraId);
    }
    if (!nombres.contains('egreso_id')) {
      await m.addColumn(db.descuentoProgramadoEmpleado, db.descuentoProgramadoEmpleado.egresoId);
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 75: foreign_key_check reportó '
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
        'Migración a schemaVersion 75: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
