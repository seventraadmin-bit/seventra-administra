import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva (Etapa 9, "Deudas y crédito: corrección y
/// cancelación individual de pagos"): 2 columnas nullable en
/// `movimiento_deuda`, sin `CHECK`/`UNIQUE` — solo `Migrator.addColumn`,
/// sin recrear ninguna tabla (mismo patrón que
/// `migrar_egreso_origen_tarjeta_v76.dart`).
///
/// - `movimiento_origen_id`: autorreferencia al `MovimientoDeuda` tipo
///   `pago` que un ajuste o una reversión corrige. Es la FK que evita
///   toda heurística para saber a qué pago pertenece una corrección
///   (nunca por monto, fecha, texto ni "el último movimiento"), y a la
///   vez el discriminador entre "ajuste de PAGO" y "ajuste de CARGO"
///   — ver el doc comment de la columna.
/// - `tarjeta_vencimiento_cubierto_anterior`: el valor que
///   `Deuda.tarjetaVencimientoCubiertoHasta` tenía antes de que un pago
///   lo avanzara, para poder deshacerlo con exactitud al cancelarlo.
///
/// El enum `TipoMovimientoDeuda` gana además el valor `reversionPago`,
/// que NO requiere migración: `tipo` es texto libre y ninguna fila
/// existente usa ese valor.
///
/// **Sin backfill, deliberado.** Las dos columnas quedan `null` en todo
/// movimiento histórico. Para `movimiento_origen_id` no hay nada que
/// reconstruir: hasta esta etapa no existía ninguna corrección ni
/// cancelación de pago individual, así que ningún ajuste preexistente
/// pertenece a un pago (todos son de cargos, con su
/// `compra_id`/`tiempo_extra_id`/`costo_adicional_id`/`egreso_gasto_id`
/// ya poblado). Para `tarjeta_vencimiento_cubierto_anterior` tampoco:
/// el valor previo de un avance ya ocurrido no está registrado en
/// ninguna parte y deducirlo sería inventarlo — un pago de TDC anterior
/// a esta etapa simplemente no podrá retroceder el ciclo al cancelarse,
/// y la UI lo reporta en vez de adivinar. En la instalación real esto
/// no afecta a nadie: hoy existe UN solo movimiento tipo `pago`, y es
/// de un préstamo (nunca de tarjeta).
Future<void> migrarCorreccionPagoDeudaV77(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final columnas = await db.customSelect("PRAGMA table_info('movimiento_deuda')").get();
    final nombres = columnas.map((fila) => fila.data['name']).toSet();

    if (!nombres.contains('movimiento_origen_id')) {
      await m.addColumn(db.movimientoDeuda, db.movimientoDeuda.movimientoOrigenId);
    }
    if (!nombres.contains('tarjeta_vencimiento_cubierto_anterior')) {
      await m.addColumn(db.movimientoDeuda, db.movimientoDeuda.tarjetaVencimientoCubiertoAnterior);
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 77: foreign_key_check reportó '
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
        'Migración a schemaVersion 77: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}
