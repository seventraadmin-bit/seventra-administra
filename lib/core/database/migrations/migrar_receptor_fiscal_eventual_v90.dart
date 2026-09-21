import 'package:drift/drift.dart';

import '../app_database.dart';

/// schemaVersion 90 — Validación operativa de Servicios Eventuales:
/// el **receptor fiscal**, separado del solicitante comercial.
///
/// **Puramente aditiva y sin ningún relleno retroactivo.** Agrega
/// cuatro columnas nullables a `servicio_eventual`
/// (`entidad_fiscal_id`, `solicitante_razon_social`,
/// `solicitante_rfc`, `solicitante_codigo_postal_fiscal`) y una a
/// `servicio_eventual_documento_fiscal`
/// (`snapshot_codigo_postal_fiscal`).
///
/// **Por qué no se rellena nada.** La tentación sería copiar
/// `solicitante_nombre` a `solicitante_razon_social` para que el
/// histórico "ya tenga" receptor fiscal. Eso es justo el error que
/// esta etapa corrige: el nombre de quien pide el servicio no es la
/// razón social a la que se factura, y afirmarlo en masa para todo el
/// histórico convertiría un dato faltante en un dato falso. Las filas
/// anteriores a la v90 quedan con `NULL`, que es exactamente lo que
/// significan: nunca se capturó.
///
/// Por la misma razón `snapshot_codigo_postal_fiscal` se queda en
/// `NULL` para los CFDI ya emitidos: tomar hoy el CP del Cliente haría
/// que un documento de ayer dijera algo que no decía.
///
/// **Nada de dinero cambia**: ni importes, ni saldos, ni pagos, ni
/// ingresos. El total de venta lo sigue derivando
/// `calcularTotalesVentaEventual` de `importe_acordado` y
/// `tratamiento_iva`, que esta migración no toca.
///
/// Idempotente, mismo criterio que v80/v87/v88/v89.
Future<void> migrarReceptorFiscalEventualV90(AppDatabase db, Migrator m) async {
  Future<Set<String>> columnasDe(String tabla) async {
    final filas = await db.customSelect('PRAGMA table_info($tabla)').get();
    return {for (final f in filas) f.data['name'] as String};
  }

  final eventual = await columnasDe('servicio_eventual');
  if (!eventual.contains('entidad_fiscal_id')) {
    await m.addColumn(db.servicioEventual, db.servicioEventual.entidadFiscalId);
  }
  if (!eventual.contains('solicitante_razon_social')) {
    await m.addColumn(db.servicioEventual, db.servicioEventual.solicitanteRazonSocial);
  }
  if (!eventual.contains('solicitante_rfc')) {
    await m.addColumn(db.servicioEventual, db.servicioEventual.solicitanteRfc);
  }
  if (!eventual.contains('solicitante_codigo_postal_fiscal')) {
    await m.addColumn(db.servicioEventual, db.servicioEventual.solicitanteCodigoPostalFiscal);
  }

  final documento = await columnasDe('servicio_eventual_documento_fiscal');
  if (!documento.contains('snapshot_codigo_postal_fiscal')) {
    await m.addColumn(
      db.servicioEventualDocumentoFiscal,
      db.servicioEventualDocumentoFiscal.snapshotCodigoPostalFiscal,
    );
  }

  // Verificación explícita, mismo criterio que las migraciones
  // anteriores del proyecto.
  final fk = await db.customSelect('PRAGMA foreign_key_check').get();
  if (fk.isNotEmpty) {
    throw StateError('migrarReceptorFiscalEventualV90: PRAGMA foreign_key_check reportó ${fk.length} problema(s).');
  }
  final integridad = await db.customSelect('PRAGMA integrity_check').getSingle();
  final resultado = integridad.data.values.first;
  if (resultado != 'ok') {
    throw StateError('migrarReceptorFiscalEventualV90: PRAGMA integrity_check devolvió "$resultado".');
  }
}
