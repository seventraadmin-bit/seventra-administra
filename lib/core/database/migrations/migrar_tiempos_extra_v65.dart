import 'package:drift/drift.dart';

import '../app_database.dart';
import '../seed/seed_data.dart';

/// Migración aditiva (Etapa "Tiempos Extra" — cobertura operativa por
/// ausencia, pedido explícito de Marlon): 3 tablas enteramente nuevas
/// (`TiempoExtra`, `TiempoExtraCostoAdicional`, `TiempoExtraEvento`),
/// una tabla nueva en Nómina (`NominaEmpleadoAusencia`), una fila nueva
/// de catálogo (`TipoModalidadTurno` → "12X24", el único valor de la
/// lista de Marlon que no existía) y una fila nueva de
/// `CodigoSecuencia` (`tiempoExtra` → `TEX`). Ninguna tabla ni columna
/// existente se modifica ni se elimina; no requiere backfill.
Future<void> migrarTiemposExtraV65(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    Future<void> crearSiNoExiste(String nombreTabla, TableInfo tabla) async {
      final tablas =
          await db.customSelect("SELECT name FROM sqlite_master WHERE type='table' AND name = '$nombreTabla'").get();
      if (tablas.isEmpty) {
        await m.createTable(tabla);
      }
    }

    await crearSiNoExiste('tiempo_extra', db.tiempoExtra);
    await crearSiNoExiste('tiempo_extra_costo_adicional', db.tiempoExtraCostoAdicional);
    await crearSiNoExiste('tiempo_extra_evento', db.tiempoExtraEvento);
    await crearSiNoExiste('nomina_empleado_ausencia', db.nominaEmpleadoAusencia);

    // Idempotente (insertOrIgnore) — cubre tanto la instalación que ya
    // tenía el resto del catálogo como una instalación nueva que ya
    // pasó por `onCreate` (que ya llama a `seedTipoModalidadTurno` con
    // la lista completa, incluyendo "12X24").
    await seedTipoModalidadTurno(db);

    await db.into(db.codigoSecuencia).insertOnConflictUpdate(
          CodigoSecuenciaCompanion.insert(entityType: 'tiempoExtra', prefijo: 'TEX', digitos: 6),
        );

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 65: foreign_key_check reportó '
        '${violacionesFk.length} violación(es) tras la migración. Migración abortada.',
      );
    }

    final resultadoIntegridad =
        await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
    final integridadOk = resultadoIntegridad.length == 1 && resultadoIntegridad.single == 'ok';
    if (!integridadOk) {
      throw StateError(
        'Migración a schemaVersion 65: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
