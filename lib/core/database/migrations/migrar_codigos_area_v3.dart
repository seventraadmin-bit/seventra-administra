import 'package:drift/drift.dart';

import '../app_database.dart';
import '../seed/seed_ids.dart';

/// Mapeo determinista de cada Área sembrada (por su id estable, nunca por
/// orden de fila) a su código definitivo — el mismo criterio que usarán
/// las Áreas nuevas creadas desde la UI (`ARE-####`).
const _codigoDefinitivoPorId = {
  SeedIds.areaOperaciones: 'ARE-0001',
  SeedIds.areaRecursosHumanos: 'ARE-0002',
  SeedIds.areaAdministracion: 'ARE-0003',
  SeedIds.areaDireccion: 'ARE-0004',
  SeedIds.areaMonitoreo: 'ARE-0005',
  SeedIds.areaReclutamiento: 'ARE-0006',
};

/// Migración de datos de la Etapa 4D (`schemaVersion` 2 → 3): unifica el
/// formato de código de Área. Antes de esta migración, las 6 Áreas
/// sembradas en 4A tenían códigos alfabéticos fijos (`OPERACIONES`,
/// `RH`, ...); de aquí en adelante todas las Áreas — sembradas o
/// creadas por la UI — usan el mismo formato `ARE-####`.
///
/// Solo toca `codigo` y el contador de `CodigoSecuencia` para `'area'`:
/// nombre, descripción, `activo` y cualquier edición que el usuario ya
/// haya hecho sobre esas filas se conservan intactos.
///
/// Determinista por id estable (`seed_ids.dart`), nunca por orden físico
/// de fila ni por el código anterior — así el resultado no depende de
/// cómo esté almacenado el archivo. Verifica *todas* las colisiones antes
/// de escribir nada: si algún `ARE-000N` ya pertenece a una fila distinta
/// de la que le corresponde, la migración falla con un mensaje claro en
/// vez de sobrescribir datos ambiguos.
Future<void> migrarCodigosAreaV3(AppDatabase db) async {
  await db.transaction(() async {
    for (final entry in _codigoDefinitivoPorId.entries) {
      final areaId = entry.key;
      final codigoDestino = entry.value;

      final ocupante = await (db.select(db.area)..where((t) => t.codigo.equals(codigoDestino))).getSingleOrNull();
      if (ocupante != null && ocupante.id != areaId) {
        throw StateError(
          'Migración de códigos de Área: "$codigoDestino" ya está en uso por la fila '
          '${ocupante.id} (nombre: ${ocupante.nombre}), no por $areaId. Migración abortada '
          'para no dejar datos ambiguos.',
        );
      }
    }

    for (final entry in _codigoDefinitivoPorId.entries) {
      final areaId = entry.key;
      final codigoDestino = entry.value;

      final fila = await (db.select(db.area)..where((t) => t.id.equals(areaId))).getSingleOrNull();
      // Esta Área sembrada no existe en esta instalación (borrada a mano,
      // o una instalación nueva que ya la sembró con el código correcto
      // directamente) — no hay nada que migrar para este id.
      if (fila == null || fila.codigo == codigoDestino) continue;

      await (db.update(db.area)..where((t) => t.id.equals(areaId))).write(
        AreaCompanion(codigo: Value(codigoDestino), updatedAt: Value(DateTime.now())),
      );
    }

    // Configura (o corrige) el contador de códigos para que la primera
    // Área nueva creada desde la UI continúe exactamente en `ARE-0007`.
    await db.into(db.codigoSecuencia).insertOnConflictUpdate(
          CodigoSecuenciaCompanion.insert(
            entityType: 'area',
            prefijo: 'ARE',
            digitos: 4,
            // 6 — mismo tamaño que `_codigoDefinitivoPorId` (no se puede
            // usar `.length` en un contexto const).
            contadorActual: const Value(6),
          ),
        );
  });
}
