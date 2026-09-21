import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración de la Etapa 4 ("Nómina — corrección, cancelación y
/// trazabilidad integral"): puramente aditiva, sin datos que migrar
/// (ningún permiso nuevo reemplaza uno viejo — `nomina.corregir` es
/// una facultad que no existía antes de esta etapa, así que no hay
/// nada que otorgar retroactivamente, a diferencia de la V70 de
/// Tiempo Extra).
///
/// 1. `nomina_evento.estado_anterior`/`estado_nuevo` (`TEXT` nullable,
///    solo `Migrator.addColumn`) — mismo shape que `PagoNominaEvento`,
///    para los nuevos tipos de evento `corregida`/`pagada`/`reabierta`/
///    `renglonEliminado`/`cancelada`. Filas históricas (`generada`/
///    `actualizadaDesdePersonal`/`movimientoModificado`/
///    `distribucionModificada`/`cerrada`) quedan con ambos campos en
///    `null` — nunca se rellenan retroactivamente.
/// 2. `nomina.motivo_cancelacion_codigo`/`motivo_cancelacion_detalle`/
///    `motivo_cancelacion_observaciones` (`TEXT` nullable) — mismo
///    shape que `Compra`/`Egreso`/`Deuda`, para la nueva cancelación
///    de Nómina completa (solo Borrador/Cerrada-sin-pagos, ver
///    `CancelarNominaUseCase`).
Future<void> migrarCorreccionNominaV72(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final columnasEvento = await db.customSelect("PRAGMA table_info('nomina_evento')").get();
    final nombresEvento = columnasEvento.map((fila) => fila.data['name']).toSet();
    if (!nombresEvento.contains('estado_anterior')) {
      await m.addColumn(db.nominaEvento, db.nominaEvento.estadoAnterior);
    }
    if (!nombresEvento.contains('estado_nuevo')) {
      await m.addColumn(db.nominaEvento, db.nominaEvento.estadoNuevo);
    }

    final columnasNomina = await db.customSelect("PRAGMA table_info('nomina')").get();
    final nombresNomina = columnasNomina.map((fila) => fila.data['name']).toSet();
    if (!nombresNomina.contains('motivo_cancelacion_codigo')) {
      await m.addColumn(db.nomina, db.nomina.motivoCancelacionCodigo);
    }
    if (!nombresNomina.contains('motivo_cancelacion_detalle')) {
      await m.addColumn(db.nomina, db.nomina.motivoCancelacionDetalle);
    }
    if (!nombresNomina.contains('motivo_cancelacion_observaciones')) {
      await m.addColumn(db.nomina, db.nomina.motivoCancelacionObservaciones);
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 72: foreign_key_check reportó '
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
        'Migración a schemaVersion 72: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
