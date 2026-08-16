import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva (Etapa 15): agrega `Empleado.bancoOtroDescripcion`
/// — el nombre del banco cuando `bancoId` apunta a la fila catálogo
/// `'OTRO'` (`SeedIds.bancoOtro`), que hasta ahora no tenía forma de
/// especificarse. Puramente aditiva, cero cambio de comportamiento para
/// datos existentes — mismo patrón que `Compra.formaPagoOtroDescripcion`.
Future<void> migrarEmpleadoV48(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final columnas = await db.customSelect("PRAGMA table_info('empleado')").get();
    final yaExiste = columnas.any((fila) => fila.data['name'] == 'banco_otro_descripcion');
    if (!yaExiste) {
      await m.addColumn(db.empleado, db.empleado.bancoOtroDescripcion);
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 48: foreign_key_check reportó '
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
        'Migración a schemaVersion 48: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
