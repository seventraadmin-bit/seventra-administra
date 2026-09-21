import 'package:drift/drift.dart';

import '../app_database.dart';

/// Columnas de `tiempo_extra` compartidas entre la forma anterior
/// (`schemaVersion` 65-84) y la forma nueva — se copian tal cual, sin
/// inventar nada. `empleado_ausente_id`/`motivo_ausencia` se copian
/// igual: sus valores existentes son reales, sólo se relaja la
/// restricción `NOT NULL` para permitir `NULL` de aquí en adelante.
///
/// Las tres columnas NUEVAS (`origen_cobertura`, `vacante_operativa_id`,
/// `descripcion_origen`) quedan deliberadamente fuera: la primera la
/// puebla el `DEFAULT` de la tabla nueva, las otras dos nacen nulas.
const _columnasTiempoExtraCompartidas = [
  'id', 'created_at', 'updated_at', 'ciclo_vida_registro',
  'folio', 'fecha', 'servicio_id', 'empleado_ausente_id', 'motivo_ausencia',
  'empleado_cubre_id', 'nombre_externo_cubre', 'turno_id',
  'monto_tiempo_extra', 'forma_pago', 'observaciones',
  'egreso_id', 'deuda_id', 'estatus', 'motivo_cancelacion',
];

/// Migración estructural (Etapa "Tiempo Extra: origen de cobertura",
/// `schemaVersion` 84 → 85).
///
/// Hasta v84 el modelo asumía que TODO TiempoExtra existía porque faltó
/// un titular: `empleado_ausente_id` y `motivo_ausencia` eran `NOT
/// NULL`. Esta migración:
///
/// 1. relaja ambas a nullable — en una plaza VACANTE no falta nadie (no
///    hay titular), y en "otro" tampoco;
/// 2. agrega el discriminador explícito `origen_cobertura`;
/// 3. agrega `vacante_operativa_id` (FK real a `VacanteOperativa`,
///    `restrict`) y `descripcion_origen`.
///
/// Requiere recrear la tabla: `ALTER TABLE ... ADD COLUMN`
/// (`Migrator.addColumn`) no puede quitar `NOT NULL`. Mismo
/// procedimiento exacto que `migrarDeudaTarjetaRevolventeV66`.
///
/// `TiempoExtra` es tabla *referenciada* por `TiempoExtraCostoAdicional`
/// y `TiempoExtraEvento` (cascade), `NominaEmpleadoAusencia` (restrict)
/// y `MovimientoDeuda.tiempoExtraId` (restrict) — mismo riesgo ya
/// documentado en `migrarServicioV24`/`migrarDeudaTarjetaRevolventeV66`:
/// `ALTER TABLE ... RENAME TO` reescribiría esas FK hacia el nombre
/// temporal. Se usa la misma corrección (`PRAGMA legacy_alter_table =
/// ON`).
///
/// **Clasificación de lo histórico** (§16 del pedido): NO se infiere
/// nada. Toda fila anterior a v85 tenía `empleado_ausente_id NOT NULL`
/// por construcción del esquema, así que toda fila histórica ES una
/// cobertura por ausencia de empleado — el `DEFAULT 'ausenciaEmpleado'`
/// de la columna nueva las clasifica sin adivinar. No se inventan
/// vacantes históricas ni se deduce "otro" para nadie. Aun así se
/// verifica explícitamente: si apareciera una fila sin empleado
/// ausente, la migración se detiene en vez de clasificarla a ciegas.
Future<void> migrarOrigenCoberturaTiempoExtraV85(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final conteoAntes =
        await db.customSelect('SELECT COUNT(*) AS n FROM tiempo_extra').map((r) => r.data['n'] as int).getSingle();

    // Ninguna fila anterior a v85 puede tener `empleado_ausente_id`
    // nulo: la columna era NOT NULL. Si el dato real dijera otra cosa,
    // clasificarla como `ausenciaEmpleado` sería inventar — se aborta.
    final anomalas = await db
        .customSelect('SELECT COUNT(*) AS n FROM tiempo_extra WHERE empleado_ausente_id IS NULL')
        .map((r) => r.data['n'] as int)
        .getSingle();
    if (anomalas > 0) {
      throw StateError(
        'Migración de TiempoExtra a schemaVersion 85: se encontraron $anomalas fila(s) '
        'sin empleado ausente, imposibles bajo el esquema v84. No se clasifican a ciegas. '
        'Migración abortada.',
      );
    }

    await db.customStatement('PRAGMA legacy_alter_table = ON');
    await db.customStatement('ALTER TABLE tiempo_extra RENAME TO tiempo_extra_old');

    // Forma *actual* de la clase Dart — ya es la forma final que
    // necesita schemaVersion 85.
    await m.createTable(db.tiempoExtra);

    final columnas = _columnasTiempoExtraCompartidas.join(', ');
    await db.customStatement('INSERT INTO tiempo_extra ($columnas) SELECT $columnas FROM tiempo_extra_old');

    final conteoDespues =
        await db.customSelect('SELECT COUNT(*) AS n FROM tiempo_extra').map((r) => r.data['n'] as int).getSingle();
    if (conteoDespues != conteoAntes) {
      throw StateError(
        'Migración de TiempoExtra a schemaVersion 85: se esperaban $conteoAntes fila(s) '
        'copiadas, se encontraron $conteoDespues. Migración abortada.',
      );
    }

    await db.customStatement('DROP TABLE tiempo_extra_old');
    await db.customStatement('PRAGMA legacy_alter_table = OFF');

    // El DEFAULT ya clasificó todo lo histórico; esto lo deja explícito
    // y protege el caso de una fila insertada sin el default.
    await db.customStatement(
      "UPDATE tiempo_extra SET origen_cobertura = 'ausenciaEmpleado' "
      'WHERE origen_cobertura IS NULL OR origen_cobertura = \'\'',
    );

    final sinClasificar = await db
        .customSelect("SELECT COUNT(*) AS n FROM tiempo_extra WHERE origen_cobertura != 'ausenciaEmpleado'")
        .map((r) => r.data['n'] as int)
        .getSingle();
    if (sinClasificar > 0) {
      throw StateError(
        'Migración de TiempoExtra a schemaVersion 85: $sinClasificar fila(s) histórica(s) '
        'quedaron con un origen distinto de ausenciaEmpleado. Migración abortada.',
      );
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración de TiempoExtra a schemaVersion 85: foreign_key_check reportó '
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
        'Migración de TiempoExtra a schemaVersion 85: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
