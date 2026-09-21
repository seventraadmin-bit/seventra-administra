import 'package:drift/drift.dart';

import '../app_database.dart';

/// Baja de empleado: conciliación de activos y vehículos pendientes
/// (schemaVersion 82).
///
/// **El gap que cierra.** Al dar de baja a un empleado quedaban
/// vigentes su `Asignacion` de Inventario y su `AsignacionVehiculo`, y
/// el modelo no podía distinguir "empleado dado de baja, bien todavía
/// pendiente de recuperar" de "asignación normal vigente".
///
/// **Por qué NO se reutilizó el cierre existente** (auditado antes de
/// migrar): cerrar una `Asignacion` con el motivo `bajaEmpleado` —que
/// ya existía en el enum— la deja en `devuelta`, emite un
/// `MovimientoInventario` de `entradaDevolucion` y pone la
/// `ArticuloUnidad` en `disponible`. Es decir, afirmaría que el radio
/// volvió al almacén y lo ofrecería para reasignar. Lo mismo en
/// Vehículos, donde `cerrar` pone `Vehiculo.estatus = disponible`.
/// Dar de baja a una persona no es recuperar un bien.
///
/// **Por qué basta una columna.** La disponibilidad ya estaba bien
/// protegida sin tocar nada: Inventario bloquea reasignar por
/// `ArticuloUnidad.estatus != disponible`, Vehículos por
/// `Vehiculo.estatus != disponible`, y el stock no serializado se
/// deriva de `MovimientoInventario`. Lo único que faltaba era poder
/// DISTINGUIR, así que no se agregó ningún estado nuevo ni se tocó
/// ningún índice — en particular `idx_asignacion_unidad_activa`, que
/// filtra `WHERE estatus = 'activa'` y habría dejado de proteger a una
/// unidad pendiente si se le hubiera inventado un estatus propio.
///
/// **Migración puramente ADITIVA. Sin backfill.** Las asignaciones
/// existentes quedan con `NULL`, que significa "asignación normal" —
/// exactamente lo que son. No se marca retroactivamente como pendiente
/// nada de un empleado que ya estaba de baja: nadie tomó esa decisión
/// en su momento, y afirmarla ahora sería inventar un hecho
/// administrativo. Si esos casos existen, se regularizan a mano.
///
/// Idempotente: cada `addColumn` se verifica contra `PRAGMA table_info`.
Future<void> migrarPendienteRecuperacionV82(AppDatabase db, Migrator m) async {
  Future<Set<String>> columnasDe(String tabla) async {
    final filas = await db.customSelect("PRAGMA table_info('$tabla')").get();
    return {for (final f in filas) f.data['name'] as String};
  }

  final asignacion = await columnasDe('asignacion');
  if (!asignacion.contains('pendiente_recuperacion_desde')) {
    await m.addColumn(db.asignacion, db.asignacion.pendienteRecuperacionDesde);
  }

  final asignacionVehiculo = await columnasDe('asignacion_vehiculo');
  if (!asignacionVehiculo.contains('pendiente_recuperacion_desde')) {
    await m.addColumn(db.asignacionVehiculo, db.asignacionVehiculo.pendienteRecuperacionDesde);
  }

  final fk = await db.customSelect('PRAGMA foreign_key_check').get();
  if (fk.isNotEmpty) {
    throw StateError('migrarPendienteRecuperacionV82: foreign_key_check reportó ${fk.length} violaciones');
  }
  final integridad = await db.customSelect('PRAGMA integrity_check').getSingle();
  final resultado = integridad.data.values.first;
  if (resultado != 'ok') {
    throw StateError('migrarPendienteRecuperacionV82: integrity_check devolvió "$resultado"');
  }
}
