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

    // Crea `direccion` (nombre real, ya libre) con la forma *actual* de
    // la clase Dart: incluye `entidad_fiscal_id`, su `UNIQUE` implícito,
    // su FK hacia `entidad_fiscal` (que ya existe — se crea antes de
    // llamar a esta función) y el `CHECK` de arco exclusivo ya sumando
    // 5 columnas en vez de 4.
    await m.createTable(db.direccion);

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
