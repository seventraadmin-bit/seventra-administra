import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración de REPARACIÓN (Etapa 15, bug real reportado en prueba
/// funcional: "No se pudo cargar la nómina").
///
/// **Causa raíz**: `migrarDescuentoInventarioNominaV54` se amplió DESPUÉS
/// de que la instalación real de desarrollo ya había migrado a
/// `schemaVersion` 54 con su forma anterior — solo agregaba
/// `descuento_inventario.nomina_empleado_id` y
/// `nomina_empleado.descuentos_inventario`, sin
/// `nomina_empleado.descuentos_inventario_pendiente_revision` (agregada
/// más tarde, en la misma etapa, sin subir el número de versión porque
/// "v54 aún no se había hecho commit"). Drift solo ejecuta `onUpgrade`
/// cuando `PRAGMA user_version` difiere de `schemaVersion`: como esa
/// instalación ya tenía `user_version = 54` guardado, la siguiente vez
/// que abrió la aplicación NO volvió a correr ningún paso de
/// migración — se quedó con `user_version = 54` pero le faltaba la
/// tercera columna. `NominaRepositoryImpl.listarEmpleados` (usada por
/// `NominasController` al abrir Personal → Nómina) selecciona TODAS las
/// columnas de `NominaEmpleado`, así que sqlite rechazaba la consulta
/// con `SqliteException: no such column: descuentos_inventario_pendiente_revision`,
/// y `NominasController._cargar` capturaba esa excepción y la mostraba
/// como "Ocurrió un error al cargar el listado de nóminas.".
///
/// **Lección aplicada aquí**: nunca amplíes una migración ya asignada a
/// un `schemaVersion` que una instalación real pudo haber alcanzado —
/// el patrón correcto de este proyecto (ya usado en 9D con 3 "ajustes
/// posteriores" en versiones 42/43/44 propias) es agregar un paso NUEVO
/// con su propio número de versión.
///
/// Esta migración es una reparación idempotente: vuelve a verificar las
/// TRES columnas que `migrarDescuentoInventarioNominaV54` debía agregar
/// (nunca asume que solo falta la tercera), así que corrige tanto una
/// instalación que se quedó a medias en 54 como una que llega aquí
/// directo desde 53 o antes (nunca pasó por la forma vieja de la
/// migración).
Future<void> migrarReparacionDescuentosInventarioV55(AppDatabase db, Migrator m) async {
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
        'Migración a schemaVersion 55: foreign_key_check reportó '
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
        'Migración a schemaVersion 55: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
