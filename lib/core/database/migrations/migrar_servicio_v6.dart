import 'package:drift/drift.dart';

import '../app_database.dart';

/// Columnas de `Servicio` tal como existían antes de la Etapa 4F.1 (15 en
/// total: las 4 de `AuditColumns` + las 11 propias) — sin cambios de
/// nombre ni de tipo, solo se usan para copiar filas y para verificar
/// conteos.
const _columnasServicioAnteriores = [
  'id', 'created_at', 'updated_at', 'ciclo_vida_registro',
  'codigo', 'cliente_id', 'nombre', 'tipo_servicio_id',
  'sucursal_administrativa_id', 'estatus', 'fecha_inicio', 'fecha_termino',
  'elementos_autorizados', 'responsable_cliente_contacto_id', 'observaciones',
];

/// Migración estructural de la Etapa 4F.1 (`schemaVersion` 2, 3, 4 o 5 →
/// 6): vuelve `sucursal_administrativa_id` nullable — requiere recrear la
/// tabla porque SQLite no permite relajar una columna `NOT NULL` vía
/// `ALTER TABLE ... ADD COLUMN` (esa cláusula solo agrega columnas
/// nuevas, nunca modifica una existente).
///
/// A diferencia de `migrarDireccionV5` (donde `Direccion` solo es tabla
/// *referenciante*, nunca referenciada), `Servicio` sí es referenciada
/// por `Direccion.servicioId`, `Ubicacion.servicioId` y
/// `Horario.servicioId` — y ahí aparece un comportamiento real de
/// SQLite que rompió la primera versión de esta migración (detectado
/// por la prueba `migración N → 6 conserva el Servicio real y sus
/// relaciones`, que hizo fallar `foreign_key_check` con 3 violaciones):
/// desde SQLite 3.25, `ALTER TABLE ... RENAME TO` **reescribe
/// automáticamente** las cláusulas `FOREIGN KEY ... REFERENCES` de
/// *otras* tablas que apuntan a la tabla renombrada, para que sigan
/// "funcionando" contra el nuevo nombre. Aquí eso es exactamente lo
/// contrario de lo que se necesita: al renombrar `servicio` a
/// `servicio_old`, SQLite reescribía las 3 FKs de arriba para que
/// dijeran `REFERENCES servicio_old (id)` — y al eliminar
/// `servicio_old` al final, esas 3 tablas quedaban apuntando a una
/// tabla que ya no existe, con su propio SQL de creación ya
/// permanentemente alterado (visible incluso comparando el snapshot de
/// esquema).
///
/// La corrección es `PRAGMA legacy_alter_table = ON` durante el
/// `RENAME`: revierte `ALTER TABLE RENAME` al comportamiento antiguo,
/// que no toca las FKs de otras tablas — así, mientras la tabla vive
/// temporalmente como `servicio_old`, las 3 tablas dependientes siguen
/// diciendo literalmente `REFERENCES servicio (id)` (un nombre que, por
/// un instante, no existe — pero SQLite no valida eso al vuelo, solo al
/// escribir o vía `foreign_key_check`) y, en cuanto `servicio` vuelve a
/// existir con los mismos `id` ya copiados, esas relaciones quedan
/// intactas sin haber sido tocadas en ningún momento. Se restaura
/// `legacy_alter_table = OFF` al final para no afectar ningún otro
/// `ALTER TABLE RENAME` futuro en la misma conexión.
///
/// El resto sigue el mismo patrón de 7 pasos que `migrarDireccionV5`:
/// crear la tabla nueva con la forma *actual* de la clase Dart, copiar
/// todos los registros, verificar conteo, eliminar la tabla anterior,
/// `foreign_key_check`, `integrity_check` — todo dentro de una única
/// transacción (revierte también los `CREATE`/`DROP TABLE` ante
/// cualquier fallo). Sin recreación de índices explícitos: `Servicio` no
/// tiene ninguno (`@TableIndex.sql`) — el único `UNIQUE` es el implícito
/// de `codigo`, que `m.createTable` ya reconstruye como parte de la
/// definición de la tabla.
///
/// Solo aplica a instalaciones que ya tenían `Servicio` físicamente
/// creado con la forma anterior (`from` 2, 3, 4 o 5) — una instalación
/// que viene de 1 ya lo crea con la forma nueva en `_createEtapa4ATables`,
/// en el mismo `onUpgrade`, antes de que esta función se invoque.
Future<void> migrarServicioV6(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final conteoAntes = await db
        .customSelect('SELECT COUNT(*) AS n FROM servicio')
        .map((r) => r.data['n'] as int)
        .getSingle();

    // Evita que SQLite reescriba las FKs de Direccion/Ubicacion/Horario
    // hacia el nombre temporal — ver nota arriba.
    await db.customStatement('PRAGMA legacy_alter_table = ON');
    await db.customStatement('ALTER TABLE servicio RENAME TO servicio_old');

    // Crea `servicio` (nombre real, ya libre) con la forma *actual* de la
    // clase Dart: `sucursal_administrativa_id` ya nullable.
    await m.createTable(db.servicio);

    final columnas = _columnasServicioAnteriores.join(', ');
    await db.customStatement(
      'INSERT INTO servicio ($columnas) SELECT $columnas FROM servicio_old',
    );

    final conteoDespues = await db
        .customSelect('SELECT COUNT(*) AS n FROM servicio')
        .map((r) => r.data['n'] as int)
        .getSingle();
    if (conteoDespues != conteoAntes) {
      throw StateError(
        'Migración de Servicio a schemaVersion 6: se esperaban $conteoAntes filas '
        'copiadas, se encontraron $conteoDespues. Migración abortada.',
      );
    }

    await db.customStatement('DROP TABLE servicio_old');
    await db.customStatement('PRAGMA legacy_alter_table = OFF');

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración de Servicio a schemaVersion 6: foreign_key_check reportó '
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
        'Migración de Servicio a schemaVersion 6: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
