import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración de la Etapa 9D (`schemaVersion` 40 → 41): expediente
/// especializado del teléfono físico — "Equipo" nunca es una tabla
/// nueva de identidad (sigue siendo `ArticuloUnidad`/`ArticuloUnidadTelefono`
/// de Inventario), así que esta migración es deliberadamente pequeña:
///
/// - `ArticuloUnidadTelefono.imei2` — dispositivos de doble SIM.
/// - `AsignacionLineaTelefonica.actorUsuarioId` y
///   `LineaTelefonicaEquipo.actorUsuarioId` — el UseCase/repositorio ya
///   recibían este parámetro desde la Etapa 9B, pero la columna nunca
///   existió y el valor se descartaba silenciosamente; se completa aquí
///   porque el punto 11 de la Etapa 9D exige que "asociación/cambio de
///   línea" sea trazable.
/// - `EquipoTelefonicoCredencial` (correo/contraseña cifrada del
///   dispositivo) y `EquipoTelefonicoEvento` (bitácora de configuración/
///   revelación/copia) — tablas enteramente nuevas.
///
/// Puramente aditiva — ninguna columna existente se toca ni se borra.
///
/// **Mismo gotcha que `migrar_auditoria_v40.dart`**: las 3 tablas que
/// reciben columnas nuevas (`ArticuloUnidadTelefono`,
/// `AsignacionLineaTelefonica`, `LineaTelefonicaEquipo`) ya existían
/// antes de `schemaVersion` 41, cada una creada en una versión histórica
/// distinta (7A, 9B). Su `createTable` original siempre lee la forma
/// *actual* de la clase Dart, así que una instalación que llegue desde
/// un origen anterior a la creación de cada tabla recibe la columna
/// gratis; una que llegue desde un origen posterior necesita
/// `addColumn` explícito. Se usa el mismo chequeo `PRAGMA table_info`
/// por columna en vez de fijar un umbral de `from`, para no repetir el
/// riesgo de fragilidad ya documentado en la Etapa 11D.
Future<void> migrarEquiposTelefonicosV41(AppDatabase db, Migrator m) async {
  Future<void> agregarColumnaSiFalta<T extends Table, D>(
    TableInfo<T, D> tabla,
    GeneratedColumn<Object> columna,
  ) async {
    final columnas = await db.customSelect("PRAGMA table_info('${tabla.actualTableName}')").get();
    final yaExiste = columnas.any((fila) => fila.data['name'] == columna.name);
    if (!yaExiste) {
      await m.addColumn(tabla, columna);
    }
  }

  await db.transaction(() async {
    await agregarColumnaSiFalta(db.articuloUnidadTelefono, db.articuloUnidadTelefono.imei2);
    await agregarColumnaSiFalta(db.asignacionLineaTelefonica, db.asignacionLineaTelefonica.actorUsuarioId);
    await agregarColumnaSiFalta(db.lineaTelefonicaEquipo, db.lineaTelefonicaEquipo.actorUsuarioId);

    await m.createTable(db.equipoTelefonicoCredencial);
    await m.createTable(db.equipoTelefonicoEvento);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 41: foreign_key_check reportó '
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
        'Migración a schemaVersion 41: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
