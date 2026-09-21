import 'package:drift/drift.dart';

import '../app_database.dart';

/// schemaVersion 91 — `EgresoFuente` como fuente canónica del efecto de
/// un Egreso sobre las cuentas, y `TransferenciaCuenta` como movimiento
/// interno de caja.
///
/// **Puramente aditiva**: tres tablas nuevas y un relleno ESTRUCTURAL.
/// Ninguna columna existente cambia; `Egreso.cuentaFinancieraId` se
/// conserva (ver su doc comment: queda *legacy*, ya no es la verdad
/// para ningún cálculo de saldo).
///
/// **El relleno no es una operación financiera.** Por cada Egreso —
/// vigente o cancelado— con `cuenta_financiera_id` no nulo se crea
/// exactamente una `EgresoFuente` por el importe completo del Egreso.
/// Es la misma salida de dinero que ya existía, escrita en el lugar
/// donde a partir de ahora se lee. No se crean Egresos ni Ingresos, no
/// se tocan saldos, estatus, fechas ni auditoría, y ningún efecto
/// financiero se duplica: desde esta versión `calcularSaldos` lee
/// **sólo** `EgresoFuente` y jamás la columna legacy, así que una
/// salida se cuenta exactamente una vez.
///
/// Se rellenan también los Egresos **cancelados**. No afectan saldo
/// —`calcularSaldos` filtra por `estatus = 'registrado'`— pero el
/// historial de la cuenta (`listarMovimientos`) sí los muestra, y
/// desde la v91 ese historial se deriva de las fuentes: sin relleno,
/// un Egreso cancelado desaparecería del historial de su cuenta.
///
/// (No existe en el proyecto ningún flujo para reactivar un Egreso
/// cancelado: `cancelar` es de una sola vía y `corregir` rechaza un
/// Egreso cancelado. El relleno NO se hace pensando en eso.)
///
/// Los Egresos financiados con TDC (`deuda_id` no nulo) **no** reciben
/// fuente: ese peso no salió de ninguna cuenta.
///
/// Idempotente, mismo criterio que v80/v87/v88/v89/v90.
Future<void> migrarOrigenFinancieroMulticuentaV91(AppDatabase db, Migrator m) async {
  Future<bool> existeTabla(String nombre) async {
    final filas = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", variables: [Variable(nombre)])
        .get();
    return filas.isNotEmpty;
  }

  if (!await existeTabla('egreso_fuente')) {
    await m.createTable(db.egresoFuente);
  }
  if (!await existeTabla('transferencia_cuenta')) {
    await m.createTable(db.transferenciaCuenta);
  }
  if (!await existeTabla('transferencia_cuenta_evento')) {
    await m.createTable(db.transferenciaCuentaEvento);
  }

  // Índices: `calcularSaldos` filtra por cuenta y `listarFuentes` por
  // Egreso. `Migrator.createTable` no crea índices que no estén
  // declarados (gotcha conocido del proyecto desde la v30), así que van
  // explícitos.
  await db.customStatement('CREATE INDEX IF NOT EXISTS idx_egreso_fuente_cuenta ON egreso_fuente (cuenta_financiera_id)');
  await db.customStatement('CREATE INDEX IF NOT EXISTS idx_egreso_fuente_egreso ON egreso_fuente (egreso_id)');
  await db.customStatement('CREATE INDEX IF NOT EXISTS idx_transferencia_origen ON transferencia_cuenta (cuenta_origen_id)');
  await db.customStatement('CREATE INDEX IF NOT EXISTS idx_transferencia_destino ON transferencia_cuenta (cuenta_destino_id)');

  // Relleno estructural. `NOT EXISTS` lo hace idempotente y evita tocar
  // un Egreso que ya tenga fuentes (por ejemplo si la migración se
  // reanuda). El `id` se genera con el mismo formato uuid v4 que usa
  // `AuditColumns.clientDefault`, aquí con `randomblob` porque esto
  // corre en SQL puro.
  await db.customStatement('''
    INSERT INTO egreso_fuente (id, created_at, updated_at, ciclo_vida_registro, egreso_id, cuenta_financiera_id, importe)
    SELECT
      lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' ||
      substr(lower(hex(randomblob(2))), 2) || '-a' ||
      substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6))),
      e.created_at,
      e.updated_at,
      'activo',
      e.id,
      e.cuenta_financiera_id,
      e.monto
    FROM egreso e
    WHERE e.cuenta_financiera_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM egreso_fuente f WHERE f.egreso_id = e.id)
  ''');

  // Verificación explícita de que el relleno cuadra: cada Egreso con
  // cuenta tiene exactamente una fuente y por su importe completo. Si
  // no, la migración falla en vez de dejar saldos distintos.
  final descuadres = await db.customSelect('''
    SELECT e.id
    FROM egreso e
    WHERE e.cuenta_financiera_id IS NOT NULL
      AND (
        (SELECT COUNT(*) FROM egreso_fuente f WHERE f.egreso_id = e.id) <> 1
        OR (SELECT COALESCE(SUM(f.importe), 0) FROM egreso_fuente f WHERE f.egreso_id = e.id) <> e.monto
      )
  ''').get();
  if (descuadres.isNotEmpty) {
    throw StateError(
      'migrarOrigenFinancieroMulticuentaV91: ${descuadres.length} Egreso(s) con cuenta '
      'no quedaron con exactamente una fuente por su importe completo.',
    );
  }

  // Siembra dual del folio TRF: esta migración cubre las bases de
  // datos EXISTENTES y `seed_data.dart` las NUEVAS. Sin las dos, el
  // folio existe en unas y no en otras — el hueco de "siembra dual"
  // que ya mordió en Entrega de Inventario y en Servicios Eventuales.
  await db.customStatement(
    'INSERT OR IGNORE INTO codigo_secuencia (entity_type, prefijo, digitos, resetea_anualmente, contador_actual) '
    "VALUES ('transferenciaCuenta', 'TRF', 6, 0, 0)",
  );

  final fk = await db.customSelect('PRAGMA foreign_key_check').get();
  if (fk.isNotEmpty) {
    throw StateError('migrarOrigenFinancieroMulticuentaV91: PRAGMA foreign_key_check reportó ${fk.length} problema(s).');
  }
  final integridad = await db.customSelect('PRAGMA integrity_check').getSingle();
  final resultado = integridad.data.values.first;
  if (resultado != 'ok') {
    throw StateError('migrarOrigenFinancieroMulticuentaV91: PRAGMA integrity_check devolvió "$resultado".');
  }
}
