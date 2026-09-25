import 'package:drift/drift.dart';

import '../app_database.dart';

/// schemaVersion 93 — Etapa 4D, respaldo portable cifrado.
///
/// **Puramente aditiva y sin una sola escritura de datos.** Crea la
/// tabla `configuracion_recuperacion_portable` y nada más: no genera
/// `backupSetId`, no crea una MWK, no inventa una clave de
/// recuperación y no configura nada automáticamente.
///
/// Es deliberado. Configurar la recuperación portable exige que una
/// persona elija una frase y guarde una clave de recuperación en papel;
/// hacerlo por su cuenta durante una migración produciría una
/// configuración que nadie puede usar y que además daría la impresión
/// de que los respaldos ya están protegidos. Tras migrar, una
/// instalación existente queda exactamente como estaba, con la
/// recuperación portable **sin configurar** hasta que el Maestro pase
/// por el asistente.
Future<void> migrarRecuperacionPortableV93(AppDatabase db, Migrator m) async {
  await m.createTable(db.configuracionRecuperacionPortable);
}
