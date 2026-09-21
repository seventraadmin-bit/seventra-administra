import 'package:drift/drift.dart';

import '../app_database.dart';

/// schemaVersion 88 — Rebanada 2 de Servicios Eventuales: el documento
/// fiscal del eventual y sus adjuntos.
///
/// **Puramente aditiva.** No toca `cuenta_por_cobrar` ni `pago`: la
/// generalización de la contraparte ya se hizo en la v87 y volver a
/// reconstruir esas dos tablas sin necesidad sería gratuito y
/// arriesgado. Aquí sólo se crean dos tablas nuevas y el índice único
/// parcial que sostiene el invariante "a lo más un documento fiscal
/// vigente por eventual".
///
/// Idempotente, mismo criterio que la v80 y la v87: la ruta `from == 1`
/// crea las tablas con la forma Dart ACTUAL, así que esta migración
/// tiene que poder correr sobre una base que ya las tiene.
Future<void> migrarCobranzaEventualV88(AppDatabase db, Migrator m) async {
  Future<bool> existeTabla(String nombre) async {
    final filas = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          variables: [Variable<String>(nombre)],
        )
        .get();
    return filas.isNotEmpty;
  }

  if (!await existeTabla('servicio_eventual_documento_fiscal')) {
    await m.createTable(db.servicioEventualDocumentoFiscal);
  }
  if (!await existeTabla('servicio_eventual_documento_fiscal_attachment')) {
    await m.createTable(db.servicioEventualDocumentoFiscalAttachment);
  }

  // El índice va aparte de `createTable` a propósito: `Migrator
  // .createTable` no emite los índices declarados con `@TableIndex`
  // (gotcha ya documentado desde la Etapa 8A). `IF NOT EXISTS` lo hace
  // idempotente por sí solo.
  await db.customStatement(
    'CREATE UNIQUE INDEX IF NOT EXISTS servicio_eventual_documento_fiscal_vigente '
    "ON servicio_eventual_documento_fiscal (servicio_eventual_id) WHERE estatus = 'registrado'",
  );

  // Verificación explícita, mismo criterio que v79/v80/v87.
  final fk = await db.customSelect('PRAGMA foreign_key_check').get();
  if (fk.isNotEmpty) {
    throw StateError('migrarCobranzaEventualV88: PRAGMA foreign_key_check reportó ${fk.length} problema(s).');
  }
  final integridad = await db.customSelect('PRAGMA integrity_check').getSingle();
  final resultado = integridad.data.values.first;
  if (resultado != 'ok') {
    throw StateError('migrarCobranzaEventualV88: PRAGMA integrity_check devolvió "$resultado".');
  }
}
