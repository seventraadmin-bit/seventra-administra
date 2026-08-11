import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración de la Etapa 11D (`schemaVersion` 39 → 40): agrega
/// `actorUsuarioId` (FK nullable a `Usuario`, `ON DELETE SET NULL`) a
/// las 15 tablas de evento/ledger del proyecto, y crea
/// `EliminacionFisicaEvento` — la única forma de eliminación física de
/// una entidad de negocio, facultad exclusiva del Usuario Maestro.
///
/// Puramente aditiva — ninguna columna existente se toca ni se borra.
/// La columna legacy `actor` (TEXT, nunca poblada con un valor real en
/// ninguna fila) permanece físicamente sin cambios en las 12 tablas
/// donde ya existía: retirarla exigiría recrear esas 12 tablas, un
/// riesgo de migración que no se justifica solo por limpieza técnica
/// (decisión explícita de Marlon). Ningún código desde esta etapa la
/// lee ni la escribe — `actorUsuarioId` es la única fuente funcional.
///
/// Sin backfill: los históricos anteriores a esta etapa quedan con
/// `actorUsuarioId = null` en todas las tablas, mostrados por la UI
/// con el mismo fallback ya usado por `UsuarioEvento` desde la Etapa
/// 11A ("Sistema / usuario no registrado").
///
/// **Gotcha real (mismo espíritu que el ya documentado en
/// `migrar_servicio_v7.dart`, pero más ancho aquí)**: las 15 tablas
/// afectadas se crearon en 15 versiones históricas distintas, cada una
/// solo una vez; su paso de creación original (`m.createTable` dentro
/// de su propia migración histórica, ej. `migrarCompraV37`) siempre lee
/// la forma *actual* de la clase Dart — que ya incluye
/// `actorUsuarioId`. Una instalación que llega desde un origen anterior
/// a la creación de una tabla dada recibe la columna gratis por ese
/// `createTable`; una que llega desde un origen posterior (la tabla ya
/// existía en su forma vieja) necesita `addColumn` explícito. Con 15
/// tablas creadas en 15 versiones distintas, fijar un único umbral de
/// `from` sería frágil y fácil de equivocar — en vez de eso, cada
/// columna se agrega solo si `PRAGMA table_info` confirma que todavía
/// no existe, sin importar `from`. `EliminacionFisicaEvento` es una
/// tabla enteramente nueva — su `createTable` sí es seguro para
/// cualquier `from <= 39`, sin necesitar este chequeo.
Future<void> migrarAuditoriaV40(AppDatabase db, Migrator m) async {
  Future<void> agregarActorUsuarioIdSiFalta<T extends Table, D>(
    TableInfo<T, D> tabla,
    GeneratedColumn<Object> columna,
  ) async {
    final columnas = await db.customSelect("PRAGMA table_info('${tabla.actualTableName}')").get();
    final yaExiste = columnas.any((fila) => fila.data['name'] == 'actor_usuario_id');
    if (!yaExiste) {
      await m.addColumn(tabla, columna);
    }
  }

  await db.transaction(() async {
    // --- actorUsuarioId en las 12 tablas que ya tenían `actor` (TEXT, legacy) ---
    await agregarActorUsuarioIdSiFalta(db.compraEvento, db.compraEvento.actorUsuarioId);
    await agregarActorUsuarioIdSiFalta(db.complementoPagoEvento, db.complementoPagoEvento.actorUsuarioId);
    await agregarActorUsuarioIdSiFalta(db.cuentaPorCobrarEvento, db.cuentaPorCobrarEvento.actorUsuarioId);
    await agregarActorUsuarioIdSiFalta(db.egresoEvento, db.egresoEvento.actorUsuarioId);
    await agregarActorUsuarioIdSiFalta(db.ingresoEvento, db.ingresoEvento.actorUsuarioId);
    await agregarActorUsuarioIdSiFalta(db.pagoEvento, db.pagoEvento.actorUsuarioId);
    await agregarActorUsuarioIdSiFalta(db.movimientoInventario, db.movimientoInventario.actorUsuarioId);
    await agregarActorUsuarioIdSiFalta(db.nominaEvento, db.nominaEvento.actorUsuarioId);
    await agregarActorUsuarioIdSiFalta(db.pagoNominaEvento, db.pagoNominaEvento.actorUsuarioId);
    await agregarActorUsuarioIdSiFalta(db.documentoPorEmitirEvento, db.documentoPorEmitirEvento.actorUsuarioId);
    await agregarActorUsuarioIdSiFalta(db.empleadoEvento, db.empleadoEvento.actorUsuarioId);
    await agregarActorUsuarioIdSiFalta(db.vehiculoKilometraje, db.vehiculoKilometraje.actorUsuarioId);

    // --- actorUsuarioId en las 3 tablas que no tenían ninguna columna de actor ---
    await agregarActorUsuarioIdSiFalta(db.recargaLineaTelefonica, db.recargaLineaTelefonica.actorUsuarioId);
    await agregarActorUsuarioIdSiFalta(db.vehiculoDocumento, db.vehiculoDocumento.actorUsuarioId);
    await agregarActorUsuarioIdSiFalta(db.vehiculoMantenimiento, db.vehiculoMantenimiento.actorUsuarioId);

    // --- Eliminación física extraordinaria del Maestro ---
    await m.createTable(db.eliminacionFisicaEvento);

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 40: foreign_key_check reportó '
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
        'Migración a schemaVersion 40: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
