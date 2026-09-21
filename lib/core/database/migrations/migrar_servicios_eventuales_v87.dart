import 'package:drift/drift.dart';

import '../app_database.dart';

/// Servicios Eventuales — Rebanada 1 (schemaVersion 87).
///
/// **Qué hace.** Crea el núcleo del dominio (evento, participantes,
/// coberturas, costos, bitácora) y **generaliza** dos tablas centrales
/// de cobranza para que una obligación pueda nacer también de una venta
/// puntual, sin falsificar un `DocumentoPorEmitir` ni un `Cliente`.
///
/// **Por qué hay que recrear `cuenta_por_cobrar` y `pago`.** SQLite no
/// permite quitar un `NOT NULL` con `ALTER TABLE`; la única vía
/// soportada es el procedimiento oficial de 12 pasos, que Drift expone
/// como `Migrator.alterTable` con un `TableMigration`. Mismo mecanismo
/// exacto que ya usó `migrarComplementoSustitutoV79` para quitar un
/// `UNIQUE` de columna.
///
/// **Preservación de datos**: `columnTransformer` va vacío a propósito
/// — ninguna columna cambia de nombre, de tipo ni de semántica, así que
/// Drift copia todas las filas tal cual. Ninguna Cuenta por cobrar,
/// Pago, Aplicación, Ingreso o Complemento existente se pierde,
/// reescribe ni cambia de `id`. Las columnas nuevas quedan en `NULL`,
/// que es exactamente lo que corresponde a una fila legacy: su origen
/// es un documento, no un eventual.
///
/// **Los CHECK nuevos se validan contra los datos reales al recrear.**
/// Toda fila histórica tiene `documento_por_emitir_id` no nulo y
/// `servicio_eventual_id` nulo, así que satisface el XOR por
/// construcción; y `cliente_id` no nulo satisface el de contraparte. Si
/// alguna no lo hiciera, la recreación fallaría y la migración entera
/// se revertiría — nunca quedaría a medias.
///
/// **Orden**: las columnas nuevas de `pago` se agregan ANTES de
/// recrearla, para que el rebuild parta de la forma completa. Y
/// `servicio_eventual` se crea antes que todo, porque las FK nuevas
/// apuntan a ella.
Future<void> migrarServiciosEventualesV87(AppDatabase db, Migrator m) async {
  // Idempotente, mismo helper exacto que `migrarVehiculosOrigenFinancieroV80`:
  // la ruta `from == 1` crea las tablas con la forma Dart ACTUAL, así
  // que llegar aquí con las columnas ya puestas es un caso normal, no
  // un error.
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

  // --- 1. El dominio nuevo ---------------------------------------
  if (!await existeTabla('servicio_eventual')) await m.createTable(db.servicioEventual);
  if (!await existeTabla('servicio_eventual_participante')) {
    await m.createTable(db.servicioEventualParticipante);
  }
  if (!await existeTabla('servicio_eventual_cobertura')) {
    await m.createTable(db.servicioEventualCobertura);
  }
  if (!await existeTabla('servicio_eventual_costo')) await m.createTable(db.servicioEventualCosto);
  if (!await existeTabla('servicio_eventual_evento')) await m.createTable(db.servicioEventualEvento);

  await db.into(db.codigoSecuencia).insert(
        CodigoSecuenciaCompanion.insert(entityType: 'servicioEventual', prefijo: 'EVT', digitos: 6),
        mode: InsertMode.insertOrIgnore,
      );

  // --- 2. FK inversas del cargo a tarjeta ------------------------
  final movimiento = await columnasDe('movimiento_deuda');
  if (!movimiento.contains('servicio_eventual_cobertura_id')) {
    await m.addColumn(db.movimientoDeuda, db.movimientoDeuda.servicioEventualCoberturaId);
  }
  if (!movimiento.contains('servicio_eventual_costo_id')) {
    await m.addColumn(db.movimientoDeuda, db.movimientoDeuda.servicioEventualCostoId);
  }

  // --- 3. Pago: contraparte nullable + origen eventual -----------
  //
  // `alterTable` se ejecuta siempre: reconstruye desde la definición
  // Dart vigente, así que en una base que ya venía con la forma nueva
  // es un no-op semántico (copia y vuelve a dejar lo mismo).
  if (!(await columnasDe('pago')).contains('servicio_eventual_id')) {
    await m.addColumn(db.pago, db.pago.servicioEventualId);
  }
  await m.alterTable(TableMigration(db.pago));

  // --- 4. Cuenta por cobrar: origen dual --------------------------
  if (!(await columnasDe('cuenta_por_cobrar')).contains('servicio_eventual_id')) {
    await m.addColumn(db.cuentaPorCobrar, db.cuentaPorCobrar.servicioEventualId);
  }
  await m.alterTable(TableMigration(db.cuentaPorCobrar));

  // --- 5. Verificación explícita, mismo criterio que v79 ----------
  final fk = await db.customSelect('PRAGMA foreign_key_check').get();
  if (fk.isNotEmpty) {
    throw StateError('migrarServiciosEventualesV87: foreign_key_check reportó ${fk.length} violaciones');
  }
  final integridad = await db.customSelect('PRAGMA integrity_check').getSingle();
  final resultado = integridad.data.values.first;
  if (resultado != 'ok') {
    throw StateError('migrarServiciosEventualesV87: integrity_check devolvió "$resultado"');
  }
}
