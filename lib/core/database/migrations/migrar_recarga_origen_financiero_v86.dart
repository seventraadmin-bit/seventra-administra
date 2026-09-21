import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración ADITIVA (Etapa "Cierre integral de Telefonía —
/// recargas", `schemaVersion` 85 → 86).
///
/// Hasta v85 una recarga de línea era sólo contexto operativo: se
/// registraban $200 reales y Finanzas no se enteraba. Esta migración
/// le da a `RecargaLineaTelefonica` el MISMO patrón dual de origen
/// financiero que ya usan `Compra`, `TiempoExtra` y
/// `VehiculoMantenimiento` —nunca una cuarta arquitectura—:
///
/// - `forma_pago` — mismo catálogo `FormaPago` de siempre.
/// - `egreso_id` — Egreso automático cuando se paga desde una cuenta.
/// - `deuda_id` — tarjeta de crédito (cargo, jamás Egreso).
/// - `movimiento_deuda.recarga_linea_telefonica_id` — FK inversa del
///   cargo, igual que `compra_id`/`tiempo_extra_id`.
///
/// Todo con `addColumn`: son columnas nuevas nullable, así que NO hace
/// falta recrear ninguna tabla (a diferencia de
/// `migrarOrigenCoberturaTiempoExtraV85`, que sí relajaba `NOT NULL`).
///
/// **Históricos (§14 del pedido): cero efecto retroactivo.** Las
/// recargas anteriores quedan con las tres columnas en `NULL`, y eso
/// —y sólo eso— las identifica como "origen financiero no
/// registrado". NO se les inventa cuenta, tarjeta, forma de pago ni
/// Egreso; NO se buscan coincidencias por fecha, importe, concepto,
/// número ni Servicio; y en particular NO se toca el Egreso manual
/// "RECARGA SALDO COYOACAN", que es una recarga real a un número
/// personal y debe seguir siendo un Egreso manual independiente.
/// Ningún balance cambia por esta migración.
///
/// El índice único parcial sobre `egreso_id` (un Egreso jamás
/// pertenece a dos recargas) se crea aquí porque `ALTER TABLE ... ADD
/// COLUMN` no admite `UNIQUE` — mismo recurso que ya usó
/// `migrarComplementoSustitutoV79`.
Future<void> migrarRecargaOrigenFinancieroV86(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final importeAntes = await db
        .customSelect("SELECT COALESCE(SUM(importe), 0) AS total FROM recarga_linea_telefonica WHERE estatus = 'registrada'")
        .map((r) => r.data['total'] as int)
        .getSingle();
    final conteoAntes = await db
        .customSelect('SELECT COUNT(*) AS n FROM recarga_linea_telefonica')
        .map((r) => r.data['n'] as int)
        .getSingle();
    final egresosAntes =
        await db.customSelect('SELECT COUNT(*) AS n FROM egreso').map((r) => r.data['n'] as int).getSingle();
    final movimientosAntes =
        await db.customSelect('SELECT COUNT(*) AS n FROM movimiento_deuda').map((r) => r.data['n'] as int).getSingle();

    Future<bool> existeColumna(String tabla, String columna) async {
      final filas = await db.customSelect("PRAGMA table_info('$tabla')").get();
      return filas.any((f) => f.data['name'] == columna);
    }

    if (!await existeColumna('recarga_linea_telefonica', 'forma_pago')) {
      await m.addColumn(db.recargaLineaTelefonica, db.recargaLineaTelefonica.formaPago);
    }
    if (!await existeColumna('recarga_linea_telefonica', 'egreso_id')) {
      await m.addColumn(db.recargaLineaTelefonica, db.recargaLineaTelefonica.egresoId);
    }
    if (!await existeColumna('recarga_linea_telefonica', 'deuda_id')) {
      await m.addColumn(db.recargaLineaTelefonica, db.recargaLineaTelefonica.deudaId);
    }
    if (!await existeColumna('movimiento_deuda', 'recarga_linea_telefonica_id')) {
      await m.addColumn(db.movimientoDeuda, db.movimientoDeuda.recargaLineaTelefonicaId);
    }

    await db.customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_recarga_linea_telefonica_egreso_unico '
      'ON recarga_linea_telefonica (egreso_id) WHERE egreso_id IS NOT NULL',
    );

    // Nada de lo anterior puede haberse movido: es estrictamente
    // aditivo. Se comprueba en vez de suponerlo.
    final conteoDespues = await db
        .customSelect('SELECT COUNT(*) AS n FROM recarga_linea_telefonica')
        .map((r) => r.data['n'] as int)
        .getSingle();
    final importeDespues = await db
        .customSelect("SELECT COALESCE(SUM(importe), 0) AS total FROM recarga_linea_telefonica WHERE estatus = 'registrada'")
        .map((r) => r.data['total'] as int)
        .getSingle();
    final egresosDespues =
        await db.customSelect('SELECT COUNT(*) AS n FROM egreso').map((r) => r.data['n'] as int).getSingle();
    final movimientosDespues =
        await db.customSelect('SELECT COUNT(*) AS n FROM movimiento_deuda').map((r) => r.data['n'] as int).getSingle();

    if (conteoDespues != conteoAntes || importeDespues != importeAntes) {
      throw StateError(
        'Migración de RecargaLineaTelefonica a schemaVersion 86: las recargas cambiaron '
        '($conteoAntes→$conteoDespues filas, $importeAntes→$importeDespues centavos). Migración abortada.',
      );
    }
    if (egresosDespues != egresosAntes || movimientosDespues != movimientosAntes) {
      throw StateError(
        'Migración de RecargaLineaTelefonica a schemaVersion 86: se crearon movimientos financieros '
        'retroactivos ($egresosAntes→$egresosDespues Egresos, $movimientosAntes→$movimientosDespues '
        'MovimientoDeuda). Ninguna recarga histórica debe alterar balances. Migración abortada.',
      );
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración de RecargaLineaTelefonica a schemaVersion 86: foreign_key_check reportó '
        '${violacionesFk.length} violación(es). Migración abortada.',
      );
    }

    final resultadoIntegridad = await db
        .customSelect('PRAGMA integrity_check')
        .map((r) => r.data['integrity_check'] as String)
        .get();
    final integridadOk = resultadoIntegridad.length == 1 && resultadoIntegridad.single == 'ok';
    if (!integridadOk) {
      throw StateError(
        'Migración de RecargaLineaTelefonica a schemaVersion 86: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
