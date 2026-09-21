import 'package:drift/drift.dart';

import '../app_database.dart';

/// Vehículos: ciclo de vida, origen financiero y trazabilidad
/// (schemaVersion 80).
///
/// **Los tres gaps que cierra**, todos confirmados contra código en la
/// auditoría de la v79:
///
/// 1. `CorregirVehiculoUseCase` podía cambiar **placas, VIN, número de
///    motor y costo de adquisición** sin `motivo`, sin `actorUsuarioId`
///    y sin dejar rastro. Era la ÚNICA excepción del proyecto: Personal,
///    Compras, Finanzas, Nómina, Deudas y Descuentos ya exigían los
///    tres. → tabla `VehiculoEvento`.
///
/// 2. `VehiculoMantenimiento.costo` existía y se totalizaba en
///    `calcularCostosVehiculo`, pero esa función se usaba en UN solo
///    lugar (la pantalla del propio vehículo). El dinero no llegaba a
///    Finanzas, ni a Reportes, ni al Dashboard. → `egresoId`/`deudaId`,
///    el mismo par dual de `Compra`/`TiempoExtra`.
///
/// 3. Mantenimiento era inmutable (`crear` y nada más): un costo mal
///    capturado no se podía corregir ni anular sin borrar historial. →
///    `estatus`/`motivoCancelacion`.
///
/// **Migración puramente ADITIVA. Sin backfill** (decisión explícita de
/// Marlon): en la instalación real existe 1 mantenimiento de $3,800 con
/// costo y sin origen financiero. Esa fila se conserva EXACTAMENTE como
/// está — `egreso_id` y `deuda_id` quedan NULL, que significa "gasto
/// histórico sin origen especificado". Inventarle una cuenta sería
/// fabricar un hecho financiero que nadie registró; mismo criterio que
/// la etapa de Egresos v76 ("no hagas backfill heurístico").
///
/// Los mantenimientos NUEVOS con costo sí exigen origen, y eso lo
/// impone el caso de uso — nunca un `CHECK`, porque el legacy debe
/// seguir siendo válido para siempre.
///
/// `Vehiculo.costoAdquisicion` NO se toca: es valor del activo, no un
/// gasto (decisión de Marlon — si el vehículo se compró, ese egreso ya
/// debería vivir en Compras; duplicarlo sería doble conteo).
///
/// Idempotente: cada `addColumn` se verifica contra `PRAGMA table_info`
/// y la tabla nueva contra `sqlite_master`.
Future<void> migrarVehiculosOrigenFinancieroV80(AppDatabase db, Migrator m) async {
  Future<Set<String>> columnasDe(String tabla) async {
    final filas = await db.customSelect("PRAGMA table_info('$tabla')").get();
    return {for (final f in filas) f.data['name'] as String};
  }

  Future<bool> existeTabla(String tabla) async {
    final filas = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      variables: [Variable<String>(tabla)],
    ).get();
    return filas.isNotEmpty;
  }

  // 1. Historial del Vehículo — el gap P0 de trazabilidad.
  if (!await existeTabla('vehiculo_evento')) {
    await m.createTable(db.vehiculoEvento);
  }

  // 2. Origen financiero + anulación del mantenimiento.
  final mantenimiento = await columnasDe('vehiculo_mantenimiento');
  if (!mantenimiento.contains('egreso_id')) {
    await m.addColumn(db.vehiculoMantenimiento, db.vehiculoMantenimiento.egresoId);
  }
  if (!mantenimiento.contains('deuda_id')) {
    await m.addColumn(db.vehiculoMantenimiento, db.vehiculoMantenimiento.deudaId);
  }
  if (!mantenimiento.contains('estatus')) {
    // `withDefault('registrado')`: las filas históricas quedan
    // registradas, que es lo que efectivamente son.
    await m.addColumn(db.vehiculoMantenimiento, db.vehiculoMantenimiento.estatus);
  }
  if (!mantenimiento.contains('motivo_cancelacion')) {
    await m.addColumn(db.vehiculoMantenimiento, db.vehiculoMantenimiento.motivoCancelacion);
  }

  // Un Egreso pertenece a un solo mantenimiento. Va como índice único
  // PARCIAL porque SQLite **no admite**
  // `ALTER TABLE … ADD COLUMN … UNIQUE` (lo rechaza con "Cannot add a
  // UNIQUE column") — mismo mecanismo que
  // `complemento_pago_vigente_por_pago` en la v79.
  await db.customStatement(
    'CREATE UNIQUE INDEX IF NOT EXISTS vehiculo_mantenimiento_egreso_unico '
    'ON vehiculo_mantenimiento (egreso_id) WHERE egreso_id IS NOT NULL',
  );

  // 3. El cargo de TDC necesita apuntar a su mantenimiento, igual que
  //    `compraId`/`tiempoExtraId`.
  final movimiento = await columnasDe('movimiento_deuda');
  if (!movimiento.contains('vehiculo_mantenimiento_id')) {
    await m.addColumn(db.movimientoDeuda, db.movimientoDeuda.vehiculoMantenimientoId);
  }

  // Verificación explícita, mismo criterio que el resto de las
  // migraciones del proyecto.
  final fk = await db.customSelect('PRAGMA foreign_key_check').get();
  if (fk.isNotEmpty) {
    throw StateError('migrarVehiculosOrigenFinancieroV80: foreign_key_check reportó ${fk.length} violaciones');
  }
  final integridad = await db.customSelect('PRAGMA integrity_check').getSingle();
  final resultado = integridad.data.values.first;
  if (resultado != 'ok') {
    throw StateError('migrarVehiculosOrigenFinancieroV80: integrity_check devolvió "$resultado"');
  }
}
