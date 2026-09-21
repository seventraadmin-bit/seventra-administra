import 'package:drift/drift.dart';

import '../app_database.dart';

/// Telefonía: trazabilidad de la línea y ciclo completo de la recarga
/// (schemaVersion 81).
///
/// **Los dos gaps que cierra**, ambos confirmados leyendo el código de
/// la v80:
///
/// 1. `CorregirLineaTelefonicaUseCase` cambiaba número, ICCID, operador
///    y modalidad de SIM **sin motivo, sin actor y sin dejar rastro** —
///    el mismo gap que Vehículos tenía antes de la v80. Telefonía no
///    tenía NINGUNA tabla de eventos propia de la línea: la Auditoría
///    central solo veía sus recargas, sus asignaciones y los eventos
///    del equipo. → tabla `LineaTelefonicaEvento`.
///
/// 2. Una recarga solo podía registrarse. Un importe mal capturado no
///    se podía corregir ni anular sin borrar la fila, y borrarla es
///    justo lo que el proyecto no hace con historial.
///    → `estatus`/`motivoCancelacion` en `RecargaLineaTelefonica`.
///
/// **Migración puramente ADITIVA. Sin backfill.** Las recargas
/// existentes quedan `registrada` por el `withDefault`, que es
/// exactamente lo que son. No se les fabrica un evento retroactivo de
/// alta: nadie presenció ese evento, y la propia fila ya es su
/// evidencia (fecha, importe, actor) desde la Etapa 11D.
///
/// **NO toca dinero.** Telefonía sigue sin generar `Egreso` ni
/// `MovimientoDeuda` — decisión deliberada documentada desde la Etapa
/// 9C, verificada de nuevo en esta etapa (cero referencias a Finanzas
/// en todo el módulo) y explícitamente fuera de alcance aquí.
///
/// Idempotente: cada `addColumn` se verifica contra `PRAGMA table_info`
/// y la tabla nueva contra `sqlite_master`.
Future<void> migrarTelefoniaTrazabilidadV81(AppDatabase db, Migrator m) async {
  Future<Set<String>> columnasDe(String tabla) async {
    final filas = await db.customSelect("PRAGMA table_info('$tabla')").get();
    return {for (final f in filas) f.data['name'] as String};
  }

  Future<bool> existeTabla(String tabla) async {
    final filas = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      variables: [Variable<String>(tabla)],
    ).get();
    return filas.isNotEmpty;
  }

  // 1. Historial de la línea — el gap de trazabilidad.
  if (!await existeTabla('linea_telefonica_evento')) {
    await m.createTable(db.lineaTelefonicaEvento);
  }

  // 2. Ciclo completo de la recarga.
  final recarga = await columnasDe('recarga_linea_telefonica');
  if (!recarga.contains('estatus')) {
    await m.addColumn(db.recargaLineaTelefonica, db.recargaLineaTelefonica.estatus);
  }
  if (!recarga.contains('motivo_cancelacion')) {
    await m.addColumn(db.recargaLineaTelefonica, db.recargaLineaTelefonica.motivoCancelacion);
  }

  // Verificación explícita, mismo criterio que el resto de las
  // migraciones del proyecto.
  final fk = await db.customSelect('PRAGMA foreign_key_check').get();
  if (fk.isNotEmpty) {
    throw StateError('migrarTelefoniaTrazabilidadV81: foreign_key_check reportó ${fk.length} violaciones');
  }
  final integridad = await db.customSelect('PRAGMA integrity_check').getSingle();
  final resultado = integridad.data.values.first;
  if (resultado != 'ok') {
    throw StateError('migrarTelefoniaTrazabilidadV81: integrity_check devolvió "$resultado"');
  }
}
