import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración estructural de la Etapa 4F.2 (`schemaVersion` 6 → 7):
/// agrega 4 columnas nuevas y nullable a `Servicio` — `entidadFiscalId`,
/// `responsableInterno`, `referenciaComercial`, `referenciaContractual`.
///
/// A diferencia de `migrarServicioV6` (que relajó `NOT NULL` y por eso
/// exigió recrear toda la tabla), esta migración es puramente aditiva:
/// SQLite permite `ALTER TABLE ... ADD COLUMN` libremente para una
/// columna nueva nullable (incluso con su propia `REFERENCES`), sin
/// tocar filas existentes ni relaciones ya establecidas — no hay
/// necesidad de recrear la tabla, ni el riesgo de reescritura de FKs de
/// otras tablas que sí aplicaba al renombrar `servicio` en la Etapa
/// 4F.1 (aquí `servicio` nunca cambia de nombre).
///
/// Solo se invoca cuando `from == 6` exactamente (ver el `onUpgrade` en
/// `app_database.dart`) — cualquier instalación que venga de una versión
/// anterior a 6 ya recibe estas 4 columnas gratis a través de
/// `migrarServicioV6`, cuyo `m.createTable(servicio)` siempre lee la
/// forma *actual* de la clase Dart. Invocarla también para esos casos
/// causaría "duplicate column name".
Future<void> migrarServicioV7(AppDatabase db, Migrator m) async {
  await m.addColumn(db.servicio, db.servicio.entidadFiscalId);
  await m.addColumn(db.servicio, db.servicio.responsableInterno);
  await m.addColumn(db.servicio, db.servicio.referenciaComercial);
  await m.addColumn(db.servicio, db.servicio.referenciaContractual);
}
