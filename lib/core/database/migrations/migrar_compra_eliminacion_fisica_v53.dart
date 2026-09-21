import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva (Etapa 15, bug real reportado por Marlon durante
/// la prueba funcional de Compras — COM-000021): estructura el motivo
/// de cancelación/eliminación física de una `Compra`.
///
/// `Compra` gana `motivo_cancelacion_codigo`/`motivo_cancelacion_detalle`/
/// `motivo_cancelacion_observaciones` — `motivo_cancelacion` (texto
/// libre) se conserva físicamente sin cambios, ningún flujo nuevo la
/// escribe (ver el doc comment de la columna legacy en `compra_table.dart`).
///
/// `EliminacionFisicaEvento` (tabla compartida entre todos los
/// dominios con eliminación física, Etapa 11D) gana `motivo_codigo`/
/// `detalle` — nullable, puramente aditivo: ningún `tipoEntidad`
/// distinto a `'compra'` los escribe todavía.
Future<void> migrarCompraEliminacionFisicaV53(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final columnasCompra = await db.customSelect("PRAGMA table_info('compra')").get();
    final nombresCompra = columnasCompra.map((fila) => fila.data['name']).toSet();
    if (!nombresCompra.contains('motivo_cancelacion_codigo')) {
      await m.addColumn(db.compra, db.compra.motivoCancelacionCodigo);
    }
    if (!nombresCompra.contains('motivo_cancelacion_detalle')) {
      await m.addColumn(db.compra, db.compra.motivoCancelacionDetalle);
    }
    if (!nombresCompra.contains('motivo_cancelacion_observaciones')) {
      await m.addColumn(db.compra, db.compra.motivoCancelacionObservaciones);
    }

    final columnasEvento = await db.customSelect("PRAGMA table_info('eliminacion_fisica_evento')").get();
    final nombresEvento = columnasEvento.map((fila) => fila.data['name']).toSet();
    if (!nombresEvento.contains('motivo_codigo')) {
      await m.addColumn(db.eliminacionFisicaEvento, db.eliminacionFisicaEvento.motivoCodigo);
    }
    if (!nombresEvento.contains('detalle')) {
      await m.addColumn(db.eliminacionFisicaEvento, db.eliminacionFisicaEvento.detalle);
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 53: foreign_key_check reportó '
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
        'Migración a schemaVersion 53: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
