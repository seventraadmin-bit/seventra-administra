import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva (Etapa 15, prueba funcional Inventario + Personal
/// + Nómina): activa la integración real "Pendiente → Aplicado" de
/// `DescuentoInventario` con Nómina — hasta ahora reservada
/// (`aplicado` nunca se escribía, ver el doc comment de
/// `EstatusDescuentoInventario`).
///
/// `DescuentoInventario` gana `nomina_empleado_id` (nullable, FK hacia
/// `NominaEmpleado`) — el renglón de Nómina donde se aplicó.
///
/// `NominaEmpleado` gana `descuentos_inventario` (entero, default 0) —
/// la suma de los `DescuentoInventario` aplicados a ese renglón,
/// distinta de `otros_descuentos` (siempre manual) — y
/// `descuentos_inventario_pendiente_revision` (booleano, default
/// falso) — Resolución explícita de Marlon: si los descuentos
/// pendientes de un Empleado superan su neto, se aplica solo hasta
/// donde alcanza y esta bandera bloquea el cierre de la Nómina hasta
/// revisión manual, nunca un total negativo silencioso.
Future<void> migrarDescuentoInventarioNominaV54(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final columnasDescuento = await db.customSelect("PRAGMA table_info('descuento_inventario')").get();
    final nombresDescuento = columnasDescuento.map((fila) => fila.data['name']).toSet();
    if (!nombresDescuento.contains('nomina_empleado_id')) {
      await m.addColumn(db.descuentoInventario, db.descuentoInventario.nominaEmpleadoId);
    }

    final columnasNominaEmpleado = await db.customSelect("PRAGMA table_info('nomina_empleado')").get();
    final nombresNominaEmpleado = columnasNominaEmpleado.map((fila) => fila.data['name']).toSet();
    if (!nombresNominaEmpleado.contains('descuentos_inventario')) {
      await m.addColumn(db.nominaEmpleado, db.nominaEmpleado.descuentosInventario);
    }
    if (!nombresNominaEmpleado.contains('descuentos_inventario_pendiente_revision')) {
      await m.addColumn(db.nominaEmpleado, db.nominaEmpleado.descuentosInventarioPendienteRevision);
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 54: foreign_key_check reportó '
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
        'Migración a schemaVersion 54: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
