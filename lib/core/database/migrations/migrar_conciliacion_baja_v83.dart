import 'package:drift/drift.dart';

import '../app_database.dart';

/// Baja laboral con conciliación obligatoria de resguardos
/// (schemaVersion 83).
///
/// **El cambio de producto.** Hasta la v82, dar de baja marcaba TODOS
/// los bienes como `pendienteRecuperacionDesde` automáticamente. Eso
/// protegía la integridad pero convertía el pendiente en un limbo: nadie
/// documentaba qué había pasado en realidad. Ahora la baja exige una
/// resolución explícita por cada bien, y el pendiente queda reservado
/// para cuando alguien DECLARA que el bien sigue con la persona.
///
/// **Por qué una tabla y no columnas.** Lo que faltaba registrar
/// —condición al recibir, destino, motivo de no entrega, autorizador,
/// receptor, fecha compromiso, justificación de no cobro— son ~10 datos
/// que solo existen en el momento de una baja. Puestos en `Asignacion`
/// estarían nulos en el 99% de las filas, y "la baja de Juan" no sería
/// consultable como una operación. Con cabecera + renglones sí lo es —
/// que es justo lo que necesitarán los reportes de bienes no
/// recuperados y de compromisos vencidos.
///
/// **Nada se duplica.** El renglón apunta por FK a la `Asignacion` o
/// `AsignacionVehiculo` real. El estatus del bien, sus movimientos de
/// inventario y su fecha de cierre siguen viviendo en su dominio; aquí
/// solo vive lo que ningún dominio sabía expresar.
///
/// **Migración puramente ADITIVA. Sin backfill.** Las bajas anteriores
/// no reciben una conciliación inventada: nadie las concilió, y
/// fabricarla ahora sería afirmar decisiones que nadie tomó. Sus
/// pendientes de la v82 siguen siendo válidos y visibles.
///
/// Siembra además la secuencia de folio `RES` para las obligaciones de
/// resguardo no recuperado, para que no salgan con prefijo de préstamo.
Future<void> migrarConciliacionBajaV83(AppDatabase db, Migrator m) async {
  Future<bool> existeTabla(String tabla) async {
    final filas = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      variables: [Variable<String>(tabla)],
    ).get();
    return filas.isNotEmpty;
  }

  if (!await existeTabla('conciliacion_baja')) {
    await m.createTable(db.conciliacionBaja);
  }
  if (!await existeTabla('conciliacion_baja_renglon')) {
    await m.createTable(db.conciliacionBajaRenglon);
  }

  // Secuencia de folio propia — idempotente.
  final existente = await (db.select(db.codigoSecuencia)
        ..where((t) => t.entityType.equals('descuentoProgramadoResguardo')))
      .getSingleOrNull();
  if (existente == null) {
    await db.into(db.codigoSecuencia).insert(
          CodigoSecuenciaCompanion.insert(
            entityType: 'descuentoProgramadoResguardo',
            prefijo: 'RES',
            digitos: 6,
          ),
        );
  }

  final fk = await db.customSelect('PRAGMA foreign_key_check').get();
  if (fk.isNotEmpty) {
    throw StateError('migrarConciliacionBajaV83: foreign_key_check reportó ${fk.length} violaciones');
  }
  final integridad = await db.customSelect('PRAGMA integrity_check').getSingle();
  final resultado = integridad.data.values.first;
  if (resultado != 'ok') {
    throw StateError('migrarConciliacionBajaV83: integrity_check devolvió "$resultado"');
  }
}
