import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración estructural de la Etapa 15 (`schemaVersion` 46 → 47) —
/// corrección real sobre un CFDI de MILUYOLE: `folioFiscal` y `uuid`
/// representaban el mismo dato fiscal (el identificador único del
/// timbre) capturado dos veces sin ninguna relación entre ambos, y
/// `serieFiscal` se prestaba a confundirse con el número de serie del
/// certificado CSD (dato distinto, sin ningún consumidor real en el
/// sistema). Se elimina `serieFiscal`, se elimina `folioFiscal`, y
/// `uuid` sobrevive como el único identificador fiscal — con
/// `COALESCE(uuid, folio_fiscal)` al copiar filas, para no perder un
/// valor ya capturado en cualquiera de los dos si una instalación real
/// ya tenía datos.
///
/// Recrea DOS tablas, en la misma transacción: `DocumentoPorEmitir`
/// (dueño original de los 3 campos) y `CuentaPorCobrar` (snapshot
/// administrativo que los copiaba tal cual, Etapa 4J.1). Ambas son
/// tablas *referenciadas* por otras (`DocumentoPorEmitir` por sus 6
/// tablas hijas + `CuentaPorCobrar`; `CuentaPorCobrar` por
/// `CuentaPorCobrarEvento`/`AplicacionPago`) — mismo riesgo y misma
/// corrección ya documentados en `migrarDocumentoPorEmitirV12`
/// (`PRAGMA legacy_alter_table = ON` durante cada `RENAME`, para que
/// SQLite no reescriba las FKs de las tablas hijas hacia el nombre
/// temporal). `DocumentoPorEmitir` se recrea primero: `CuentaPorCobrar`
/// referencia sus `id`, que se preservan exactos en la copia, así que
/// el orden no genera ninguna violación de FK intermedia.
///
/// **Cada tabla se recrea solo si `folio_fiscal` todavía existe
/// físicamente** — chequeo `PRAGMA table_info`, nunca un umbral de
/// `from` (mismo criterio ya documentado en
/// `migrar_equipos_telefonicos_v41.dart`, para no repetir la
/// fragilidad de la Etapa 11D). Ambas tablas se crean, en cualquier
/// origen `from` anterior a su propia versión de nacimiento (11/14),
/// directamente con `m.createTable` usando la forma *actual* de la
/// clase Dart — que a partir de esta corrección ya nace sin
/// `serieFiscal`/`folioFiscal` — así que instalaciones que nunca
/// llegaron a tener esas columnas no deben (ni pueden) recrearse.
Future<void> migrarDocumentoPorEmitirUuidV47(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    await _recrearDocumentoPorEmitir(db, m);
    await _recrearCuentaPorCobrar(db, m);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración de DocumentoPorEmitir/CuentaPorCobrar a schemaVersion 47: foreign_key_check '
        'reportó ${violacionesFk.length} violación(es) tras la migración. Migración abortada.',
      );
    }

    final resultadoIntegridad = await db
        .customSelect('PRAGMA integrity_check')
        .map((r) => r.data['integrity_check'] as String)
        .get();
    final integridadOk = resultadoIntegridad.length == 1 && resultadoIntegridad.single == 'ok';
    if (!integridadOk) {
      throw StateError(
        'Migración de DocumentoPorEmitir/CuentaPorCobrar a schemaVersion 47: integrity_check '
        'reportó problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}

const _columnasDocumentoPorEmitirNuevas = [
  'id', 'created_at', 'updated_at', 'ciclo_vida_registro',
  'codigo', 'cliente_id', 'entidad_fiscal_id', 'tipo_documento', 'agrupacion',
  'metodo', 'requiere_complemento', 'periodo_inicio', 'periodo_fin',
  'fecha_emision_programada', 'fecha_procesamiento_programada', 'fecha_pago_esperado_programada',
  'generation_key', 'importe_base_esperado', 'ajuste_manual', 'motivo_ajuste',
  'importe_final_esperado', 'estatus', 'motivo_estatus', 'observaciones',
  'folio_documento', 'uuid', 'fecha_emision_real', 'importe_emitido',
  'observaciones_emision', 'fecha_envio', 'observaciones_envio',
];

Future<void> _recrearDocumentoPorEmitir(AppDatabase db, Migrator m) async {
  final columnas0 = await db.customSelect("PRAGMA table_info('documento_por_emitir')").get();
  final tieneFolioFiscal = columnas0.any((fila) => fila.data['name'] == 'folio_fiscal');
  if (!tieneFolioFiscal) return;

  final conteoAntes = await db
      .customSelect('SELECT COUNT(*) AS n FROM documento_por_emitir')
      .map((r) => r.data['n'] as int)
      .getSingle();

  await db.customStatement('PRAGMA legacy_alter_table = ON');
  await db.customStatement('ALTER TABLE documento_por_emitir RENAME TO documento_por_emitir_old');

  await m.createTable(db.documentoPorEmitir);

  final columnas = _columnasDocumentoPorEmitirNuevas.join(', ');
  await db.customStatement(
    'INSERT INTO documento_por_emitir ($columnas) '
    'SELECT id, created_at, updated_at, ciclo_vida_registro, '
    'codigo, cliente_id, entidad_fiscal_id, tipo_documento, agrupacion, '
    'metodo, requiere_complemento, periodo_inicio, periodo_fin, '
    'fecha_emision_programada, fecha_procesamiento_programada, fecha_pago_esperado_programada, '
    'generation_key, importe_base_esperado, ajuste_manual, motivo_ajuste, '
    'importe_final_esperado, estatus, motivo_estatus, observaciones, '
    'folio_documento, COALESCE(uuid, folio_fiscal), fecha_emision_real, importe_emitido, '
    'observaciones_emision, fecha_envio, observaciones_envio '
    'FROM documento_por_emitir_old',
  );

  final conteoDespues = await db
      .customSelect('SELECT COUNT(*) AS n FROM documento_por_emitir')
      .map((r) => r.data['n'] as int)
      .getSingle();
  if (conteoDespues != conteoAntes) {
    throw StateError(
      'Migración de DocumentoPorEmitir a schemaVersion 47: se esperaban $conteoAntes filas '
      'copiadas, se encontraron $conteoDespues. Migración abortada.',
    );
  }

  await db.customStatement('DROP TABLE documento_por_emitir_old');
  await db.customStatement('PRAGMA legacy_alter_table = OFF');
}

const _columnasCuentaPorCobrarNuevas = [
  'id', 'created_at', 'updated_at', 'ciclo_vida_registro',
  'documento_por_emitir_id', 'cliente_id', 'tipo_documento', 'metodo', 'requiere_complemento',
  'folio_documento', 'uuid', 'fecha_emision_real', 'importe_emitido',
  'saldo_original', 'saldo_pendiente', 'moneda', 'estatus', 'fecha_vencimiento', 'observaciones',
];

Future<void> _recrearCuentaPorCobrar(AppDatabase db, Migrator m) async {
  final columnas0 = await db.customSelect("PRAGMA table_info('cuenta_por_cobrar')").get();
  final tieneFolioFiscal = columnas0.any((fila) => fila.data['name'] == 'folio_fiscal');
  if (!tieneFolioFiscal) return;

  final conteoAntes = await db
      .customSelect('SELECT COUNT(*) AS n FROM cuenta_por_cobrar')
      .map((r) => r.data['n'] as int)
      .getSingle();

  await db.customStatement('PRAGMA legacy_alter_table = ON');
  await db.customStatement('ALTER TABLE cuenta_por_cobrar RENAME TO cuenta_por_cobrar_old');

  await m.createTable(db.cuentaPorCobrar);

  final columnas = _columnasCuentaPorCobrarNuevas.join(', ');
  await db.customStatement(
    'INSERT INTO cuenta_por_cobrar ($columnas) '
    'SELECT id, created_at, updated_at, ciclo_vida_registro, '
    'documento_por_emitir_id, cliente_id, tipo_documento, metodo, requiere_complemento, '
    'folio_documento, COALESCE(uuid, folio_fiscal), fecha_emision_real, importe_emitido, '
    'saldo_original, saldo_pendiente, moneda, estatus, fecha_vencimiento, observaciones '
    'FROM cuenta_por_cobrar_old',
  );

  final conteoDespues = await db
      .customSelect('SELECT COUNT(*) AS n FROM cuenta_por_cobrar')
      .map((r) => r.data['n'] as int)
      .getSingle();
  if (conteoDespues != conteoAntes) {
    throw StateError(
      'Migración de CuentaPorCobrar a schemaVersion 47: se esperaban $conteoAntes filas '
      'copiadas, se encontraron $conteoDespues. Migración abortada.',
    );
  }

  await db.customStatement('DROP TABLE cuenta_por_cobrar_old');
  await db.customStatement('PRAGMA legacy_alter_table = OFF');
}
