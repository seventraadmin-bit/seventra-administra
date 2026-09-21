import 'package:drift/drift.dart';

import '../app_database.dart';

/// Trazabilidad de Comercial: Cliente, Servicio y Configuración de cobro
/// (schemaVersion 84).
///
/// **El hueco que cierra.** Hasta la v83, todo el bloque Comercial podía
/// cambiar sin dejar rastro: corregir la razón social de una Entidad
/// fiscal, cambiar el precio de un Servicio, terminar un Servicio o
/// abrir una vigencia de cobro no registraban ni quién lo hizo, ni
/// cuándo, ni por qué, ni qué valor había antes. Lo único auditado del
/// área era la Agenda de documentos por emitir y la eliminación física.
/// Personal, Nómina, Vehículos, Telefonía, Inventario y Deudas llevaban
/// años con su bitácora; Comercial no.
///
/// **Tres tablas, no una.** Cada una corresponde a un permiso real que
/// ya existe (`clientes.*`, `servicios.*`, `configuracionCobro.*`), y el
/// agregado de cada una es el que ya declara el catálogo de permisos:
/// Entidad fiscal y Contacto cuelgan del Cliente; la configuración
/// comercial (precio, elementos, turno, IVA) cuelga del Servicio. No se
/// crea ninguna tabla catch-all: Auditoría central sigue siendo una
/// PROYECCIÓN de los eventos de dominio, nunca su fuente.
///
/// **Migración puramente ADITIVA. Sin backfill.** Las operaciones
/// anteriores no reciben eventos inventados: nadie registró quién las
/// hizo, y fabricar un actor o un motivo ahora sería afirmar cosas que
/// nunca ocurrieron. El historial arranca en el momento de esta
/// implementación; los datos existentes quedan intactos.
///
/// Los índices son por entidad + fecha: es exactamente como consulta la
/// Auditoría central (rango de fechas) y como consulta el expediente de
/// cada registro (todos los eventos de UNO).
Future<void> migrarTrazabilidadComercialV84(AppDatabase db, Migrator m) async {
  Future<bool> existeTabla(String tabla) async {
    final filas = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      variables: [Variable<String>(tabla)],
    ).get();
    return filas.isNotEmpty;
  }

  if (!await existeTabla('cliente_evento')) {
    await m.createTable(db.clienteEvento);
  }
  if (!await existeTabla('servicio_evento')) {
    await m.createTable(db.servicioEvento);
  }
  if (!await existeTabla('configuracion_cobro_evento')) {
    await m.createTable(db.configuracionCobroEvento);
  }

  // `createTable` no crea índices (gotcha ya documentado desde la Etapa
  // 8A): se declaran aquí, idempotentes.
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_cliente_evento_cliente_fecha ON cliente_evento (cliente_id, fecha_hora)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_cliente_evento_fecha ON cliente_evento (fecha_hora)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_servicio_evento_servicio_fecha ON servicio_evento (servicio_id, fecha_hora)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_servicio_evento_fecha ON servicio_evento (fecha_hora)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_configuracion_cobro_evento_config_fecha '
    'ON configuracion_cobro_evento (configuracion_cobro_id, fecha_hora)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_configuracion_cobro_evento_fecha ON configuracion_cobro_evento (fecha_hora)',
  );

  final fk = await db.customSelect('PRAGMA foreign_key_check').get();
  if (fk.isNotEmpty) {
    throw StateError('migrarTrazabilidadComercialV84: foreign_key_check reportó ${fk.length} violaciones');
  }
  final integridad = await db.customSelect('PRAGMA integrity_check').getSingle();
  final resultado = integridad.data.values.first;
  if (resultado != 'ok') {
    throw StateError('migrarTrazabilidadComercialV84: integrity_check devolvió "$resultado"');
  }
}
