import 'package:drift/drift.dart';

import '../app_database.dart';

/// schemaVersion 89 — Rebanada 3 de Servicios Eventuales: el
/// tratamiento de IVA del precio acordado.
///
/// **Puramente aditiva, y deliberadamente inerte para lo histórico.**
/// Sólo agrega `servicio_eventual.tratamiento_iva`. NO recalcula
/// `saldoOriginal`, `saldoPendiente`, `importeEmitido`, aplicaciones,
/// pagos ni ingresos: el tratamiento de IVA explica una venta, no
/// reescribe dinero que ya se movió.
///
/// **Por qué `noAplica` para las filas de la v88.** Ahí
/// `importeAcordado` ERA el total a cobrar. El total derivado tiene que
/// seguir siendo exactamente ese, y hay dos tratamientos que lo
/// cumplen:
///
///   noAplica    → total = importeAcordado        ✔ conserva
///   ivaIncluido → total = importeAcordado        ✔ conserva
///   masIva      → total = importeAcordado × 1.16 ✘ lo cambiaría
///
/// Entre los dos que conservan, `noAplica` es el único que además **no
/// inventa un desglose**: con `ivaIncluido`, la pantalla empezaría a
/// afirmar que esas ventas históricas contenían un IVA que nadie
/// capturó nunca. Se elige el que no afirma de más — el `DEFAULT` de la
/// columna hace exactamente eso para las filas existentes.
///
/// Idempotente, mismo criterio que v80/v87/v88.
Future<void> migrarIvaEventualV89(AppDatabase db, Migrator m) async {
  Future<Set<String>> columnasDe(String tabla) async {
    final filas = await db.customSelect('PRAGMA table_info($tabla)').get();
    return {for (final f in filas) f.data['name'] as String};
  }

  final columnas = await columnasDe('servicio_eventual');
  if (!columnas.contains('tratamiento_iva')) {
    await m.addColumn(db.servicioEventual, db.servicioEventual.tratamientoIva);
  }

  // Verificación explícita, mismo criterio que las migraciones
  // anteriores del proyecto.
  final fk = await db.customSelect('PRAGMA foreign_key_check').get();
  if (fk.isNotEmpty) {
    throw StateError('migrarIvaEventualV89: PRAGMA foreign_key_check reportó ${fk.length} problema(s).');
  }
  final integridad = await db.customSelect('PRAGMA integrity_check').getSingle();
  final resultado = integridad.data.values.first;
  if (resultado != 'ok') {
    throw StateError('migrarIvaEventualV89: PRAGMA integrity_check devolvió "$resultado".');
  }
}
