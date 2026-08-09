import 'package:drift/drift.dart';

import '../app_database.dart';

/// Columnas de `Direccion` tal como existían antes de la Etapa 5A (21
/// en total: las 4 de `AuditColumns` + las 17 propias, forma de la
/// Etapa 4E.2) — se usan para copiar filas.
const _columnasDireccionAnteriores = [
  'id', 'created_at', 'updated_at', 'ciclo_vida_registro',
  'empresa_id', 'sucursal_id', 'cliente_id', 'servicio_id', 'entidad_fiscal_id',
  'tipo_direccion', 'es_principal', 'calle', 'numero_exterior',
  'numero_interior', 'colonia', 'municipio_alcaldia', 'ciudad_localidad',
  'estado', 'codigo_postal', 'pais', 'referencias',
];

/// Migración estructural de la Etapa 5A (`schemaVersion` 2 a 17 → 18):
/// agrega la sexta pata del arco exclusivo de `Direccion`
/// (`empleadoId`, domicilio del Empleado) y actualiza sus `CHECK` —
/// requiere recrear la tabla, mismo motivo que `migrarDireccionV5`: no
/// se puede agregar una columna `UNIQUE` ni modificar un `CHECK`
/// existente vía `ALTER TABLE ... ADD COLUMN`.
///
/// A diferencia de `Attachment`, ninguna tabla tiene una FK que apunte
/// *hacia* `Direccion` — no necesita `PRAGMA legacy_alter_table`, un
/// `RENAME` simple es suficiente.
///
/// Requiere que `empleado` ya exista (su FK la referencia) — por eso
/// corre después de crear esa tabla en `onUpgrade`. Solo aplica a
/// instalaciones que ya tenían `Direccion` físicamente creada con la
/// forma anterior (`from` 2 a 17) — un origen `from == 1` ya la crea
/// con la forma *actual* en `_createEtapa4ATables`, en el mismo
/// `onUpgrade`, antes de que esta función se invoque.
Future<void> migrarDireccionV18(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final conteoAntes = await db
        .customSelect('SELECT COUNT(*) AS n FROM direccion')
        .map((r) => r.data['n'] as int)
        .getSingle();

    await db.customStatement('ALTER TABLE direccion RENAME TO direccion_old');

    // Crea `direccion` (nombre real, ya libre) con la forma *actual* de
    // la clase Dart: incluye `empleado_id`, su `UNIQUE` implícito, su
    // FK hacia `empleado` (que ya existe) y el `CHECK` de arco
    // exclusivo ya sumando 6 columnas en vez de 5.
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
        'Migración de Direccion a schemaVersion 18: se esperaban $conteoAntes filas '
        'copiadas, se encontraron $conteoDespues. Migración abortada.',
      );
    }

    await db.customStatement('DROP TABLE direccion_old');

    // Reconstruye los dos índices explícitos que ya existían — se
    // pierden junto con `direccion_old` al recrear la tabla.
    await m.createIndex(db.idxDireccionClienteTipoPrincipal);
    await m.createIndex(db.idxDireccionCliente);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración de Direccion a schemaVersion 18: foreign_key_check reportó '
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
        'Migración de Direccion a schemaVersion 18: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
