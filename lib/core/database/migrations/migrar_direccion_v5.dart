import 'package:drift/drift.dart';

import '../app_database.dart';

/// Columnas de `Direccion` tal como existían antes de la Etapa 4E.2 (20
/// en total: las 4 de `AuditColumns` + las 16 propias) — se usa tanto
/// para copiar filas como para verificar, por PRAGMA, que la tabla
/// nueva las conserva todas más `entidad_fiscal_id`.
const _columnasDireccionAnteriores = [
  'id', 'created_at', 'updated_at', 'ciclo_vida_registro',
  'empresa_id', 'sucursal_id', 'cliente_id', 'servicio_id',
  'tipo_direccion', 'es_principal', 'calle', 'numero_exterior',
  'numero_interior', 'colonia', 'municipio_alcaldia', 'ciudad_localidad',
  'estado', 'codigo_postal', 'pais', 'referencias',
];

/// Migración estructural de la Etapa 4E.2 (`schemaVersion` 2, 3 o 4 →
/// 5): agrega la quinta pata del arco exclusivo de `Direccion`
/// (`entidadFiscalId`) y actualiza sus `CHECK` — requiere recrear la
/// tabla porque SQLite no permite agregar una columna con `UNIQUE` ni
/// modificar un `CHECK` existente vía `ALTER TABLE ... ADD COLUMN`.
///
/// Sigue exactamente los 7 pasos pedidos: (1) crear la tabla nueva ya
/// con la forma actual, (2) copiar todos los registros existentes,
/// (3) verificar conteo, (4) eliminar la tabla anterior, (5) renombrar
/// —aquí se hace al revés por simplicidad: se renombra la ANTERIOR a un
/// nombre temporal primero, para que `m.createTable` pueda crear
/// `direccion` con su nombre real desde el principio, sin necesitar un
/// segundo `RENAME`—, (6) recrear índices, (7) `foreign_key_check`. Se
/// agrega además `integrity_check`, pedido explícitamente. Todo dentro
/// de una única transacción: si cualquier paso falla, SQLite revierte
/// también los `CREATE`/`DROP TABLE` (son transaccionales) y la base
/// queda exactamente como estaba en `schemaVersion` 4 — nunca a medias.
///
/// Solo aplica a instalaciones que ya tenían `Direccion` físicamente
/// creada con la forma anterior (`from` 2, 3 o 4) — una instalación que
/// viene de 1 ya la crea con la forma nueva en `_createEtapa4ATables`,
/// en el mismo `onUpgrade`, antes de que esta función se invoque.
Future<void> migrarDireccionV5(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final conteoAntes = await db
        .customSelect('SELECT COUNT(*) AS n FROM direccion')
        .map((r) => r.data['n'] as int)
        .getSingle();

    await db.customStatement('ALTER TABLE direccion RENAME TO direccion_old');

    // Crea `direccion` (nombre real, ya libre) con la forma exacta que
    // tenía en schemaVersion 5: incluye `entidad_fiscal_id`, su
    // `UNIQUE` implícito, su FK hacia `entidad_fiscal` y el `CHECK` de
    // arco exclusivo ya sumando 5 columnas en vez de 4. SQL fijo, no
    // `m.createTable(db.direccion)` — desde la Etapa 5A, `db.direccion`
    // refleja la forma *actual* (6 vías, con `empleado_id`), no la
    // forma histórica de esta migración; a diferencia de las
    // migraciones de `Attachment` (que sí fallarían por columnas
    // faltantes), aquí el riesgo es más sutil: pruebas que validan
    // contra el objetivo nominal exacto (`schemaVersion` 5, no
    // `_currentSchemaVersion`) detectan la columna de más y fallan.
    await db.customStatement('''
      CREATE TABLE "direccion" (
        "id" TEXT NOT NULL,
        "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
        "updated_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
        "ciclo_vida_registro" TEXT NOT NULL DEFAULT 'activo',
        "empresa_id" TEXT NULL UNIQUE,
        "sucursal_id" TEXT NULL UNIQUE,
        "cliente_id" TEXT NULL,
        "servicio_id" TEXT NULL UNIQUE,
        "entidad_fiscal_id" TEXT NULL UNIQUE,
        "tipo_direccion" TEXT NOT NULL,
        "es_principal" INTEGER NOT NULL DEFAULT 1 CHECK ("es_principal" IN (0, 1)),
        "calle" TEXT NOT NULL,
        "numero_exterior" TEXT NOT NULL,
        "numero_interior" TEXT NULL,
        "colonia" TEXT NOT NULL,
        "municipio_alcaldia" TEXT NOT NULL,
        "ciudad_localidad" TEXT NULL,
        "estado" TEXT NOT NULL,
        "codigo_postal" TEXT NOT NULL,
        "pais" TEXT NOT NULL DEFAULT 'México',
        "referencias" TEXT NULL,
        PRIMARY KEY ("id"),
        FOREIGN KEY (empresa_id) REFERENCES empresa (id) ON DELETE RESTRICT,
        FOREIGN KEY (sucursal_id) REFERENCES sucursal (id) ON DELETE RESTRICT,
        FOREIGN KEY (cliente_id) REFERENCES cliente (id) ON DELETE RESTRICT,
        FOREIGN KEY (servicio_id) REFERENCES servicio (id) ON DELETE RESTRICT,
        FOREIGN KEY (entidad_fiscal_id) REFERENCES entidad_fiscal (id) ON DELETE RESTRICT,
        CHECK ((CASE WHEN empresa_id IS NOT NULL THEN 1 ELSE 0 END +
                CASE WHEN sucursal_id IS NOT NULL THEN 1 ELSE 0 END +
                CASE WHEN cliente_id IS NOT NULL THEN 1 ELSE 0 END +
                CASE WHEN servicio_id IS NOT NULL THEN 1 ELSE 0 END +
                CASE WHEN entidad_fiscal_id IS NOT NULL THEN 1 ELSE 0 END) = 1),
        CHECK (empresa_id IS NULL OR tipo_direccion = 'fiscal'),
        CHECK (servicio_id IS NULL OR tipo_direccion = 'operativa'),
        CHECK (sucursal_id IS NULL OR tipo_direccion IN ('administrativa', 'operativa')),
        CHECK (entidad_fiscal_id IS NULL OR tipo_direccion = 'fiscal')
      )
    ''');

    final columnas = _columnasDireccionAnteriores.join(', ');
    await db.customStatement(
      'INSERT INTO direccion ($columnas) SELECT $columnas FROM direccion_old',
    );

    final conteoDespues = await db
        .customSelect('SELECT COUNT(*) AS n FROM direccion')
        .map((r) => r.data['n'] as int)
        .getSingle();
    if (conteoDespues != conteoAntes) {
      throw StateError(
        'Migración de Direccion a schemaVersion 5: se esperaban $conteoAntes filas '
        'copiadas, se encontraron $conteoDespues. Migración abortada.',
      );
    }

    await db.customStatement('DROP TABLE direccion_old');

    // Reconstruye los dos índices explícitos que ya existían — ninguno
    // depende de `entidad_fiscal_id`, pero al recrear la tabla se
    // pierden junto con `direccion_old` y deben volver a crearse.
    await m.createIndex(db.idxDireccionClienteTipoPrincipal);
    await m.createIndex(db.idxDireccionCliente);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración de Direccion a schemaVersion 5: foreign_key_check reportó '
        '${violacionesFk.length} violación(es) tras la migración. Migración abortada.',
      );
    }

    final resultadoIntegridad = await db
        .customSelect('PRAGMA integrity_check')
        .map((r) => r.data['integrity_check'] as String)
        .get();
    final integridadOk = resultadoIntegridad.length == 1 && resultadoIntegridad.single == 'ok';
    if (!integridadOk) {
      throw StateError(
        'Migración de Direccion a schemaVersion 5: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
