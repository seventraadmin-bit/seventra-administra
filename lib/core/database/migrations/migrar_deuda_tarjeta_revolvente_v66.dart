import 'package:drift/drift.dart';

import '../app_database.dart';

/// Columnas de `Deuda` compartidas entre la forma anterior
/// (`schemaVersion` 61-65) y la forma nueva — se copian tal cual, sin
/// inventar nada. `importe_original`/`fecha_origen` se copian igual
/// (sus valores existentes son reales, solo se relaja la restricción
/// para permitir `NULL` de aquí en adelante).
const _columnasDeudaCompartidas = [
  'id', 'created_at', 'updated_at', 'ciclo_vida_registro',
  'folio', 'nombre', 'tipo', 'acreedor', 'fecha_origen', 'importe_original', 'saldo_actual',
  'fecha_vencimiento', 'pago_programado', 'periodicidad', 'tasa_interes', 'referencia', 'observaciones',
  'estatus', 'motivo_cancelacion',
  'tarjeta_ultimos_digitos', 'tarjeta_limite_credito', 'tarjeta_dia_corte', 'tarjeta_dia_pago', 'tarjeta_pago_minimo',
];

/// Migración estructural (Etapa "Tarjeta de crédito como línea
/// revolvente", `schemaVersion` 65 → 66): vuelve nullable
/// `Deuda.importeOriginal`/`fechaOrigen` (una TDC no tiene un "importe
/// original" real ni siempre se conoce su fecha de apertura exacta —
/// ambos siguen siendo obligatorios para tipos de deuda fija, validado
/// en `RegistrarDeudaUseCase`, nunca en el esquema) y agrega 3 columnas
/// nuevas: `fechaSaldoInicial` (fecha real del saldo capturado al
/// alta — distinta de `fechaOrigen`), `tarjetaReglaFechaPago` y
/// `tarjetaDiasDespuesCorte` (modelo explícito de la regla de fecha
/// límite de pago).
///
/// Requiere recrear la tabla: `importeOriginal` lleva `CHECK` (relajado
/// a `IS NULL OR > 0`) y `ALTER TABLE ... ADD COLUMN`
/// (`Migrator.addColumn`) no puede quitar `NOT NULL` ni tocar
/// restricciones existentes — solo agregar columnas nuevas. Mismo
/// motivo estructural que `migrarServicioV24`.
///
/// `Deuda` es tabla *referenciada* (`MovimientoDeuda.deudaId` cascade,
/// `Compra.deudaId` nullable) — mismo riesgo ya documentado en
/// `migrarServicioV24`: `ALTER TABLE ... RENAME TO` reescribiría esas
/// FK hacia el nombre temporal. Se usa la misma corrección
/// (`PRAGMA legacy_alter_table = ON`).
///
/// Backfill (nunca inventa nada — solo hace explícito lo que ya era
/// cierto o copia un dato real ya existente):
/// - `tarjeta_regla_fecha_pago = 'diaFijo'` para toda fila con
///   `tarjeta_dia_pago IS NOT NULL` — esa era la única regla que existía
///   antes de esta etapa.
/// - `fecha_saldo_inicial` = la `fecha` de su propio
///   `MovimientoDeuda` con `tipo = 'altaInicial'` (si existe) — el dato
///   real ya estaba en la bitácora, solo se copia a la Deuda.
Future<void> migrarDeudaTarjetaRevolventeV66(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final conteoAntes =
        await db.customSelect('SELECT COUNT(*) AS n FROM deuda').map((r) => r.data['n'] as int).getSingle();

    await db.customStatement('PRAGMA legacy_alter_table = ON');
    await db.customStatement('ALTER TABLE deuda RENAME TO deuda_old');

    // Forma *actual* de la clase Dart — ya es la forma final que
    // necesita schemaVersion 66.
    await m.createTable(db.deuda);

    final columnas = _columnasDeudaCompartidas.join(', ');
    await db.customStatement('INSERT INTO deuda ($columnas) SELECT $columnas FROM deuda_old');

    final conteoDespues =
        await db.customSelect('SELECT COUNT(*) AS n FROM deuda').map((r) => r.data['n'] as int).getSingle();
    if (conteoDespues != conteoAntes) {
      throw StateError(
        'Migración de Deuda a schemaVersion 66: se esperaban $conteoAntes filas '
        'copiadas, se encontraron $conteoDespues. Migración abortada.',
      );
    }

    await db.customStatement('DROP TABLE deuda_old');
    await db.customStatement('PRAGMA legacy_alter_table = OFF');

    await db.customStatement('''
      UPDATE deuda
      SET tarjeta_regla_fecha_pago = 'diaFijo'
      WHERE tarjeta_dia_pago IS NOT NULL
    ''');

    await db.customStatement('''
      UPDATE deuda
      SET fecha_saldo_inicial = (
        SELECT fecha FROM movimiento_deuda
        WHERE movimiento_deuda.deuda_id = deuda.id AND movimiento_deuda.tipo = 'altaInicial'
        LIMIT 1
      )
      WHERE EXISTS (
        SELECT 1 FROM movimiento_deuda
        WHERE movimiento_deuda.deuda_id = deuda.id AND movimiento_deuda.tipo = 'altaInicial'
      )
    ''');

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración de Deuda a schemaVersion 66: foreign_key_check reportó '
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
        'Migración de Deuda a schemaVersion 66: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
