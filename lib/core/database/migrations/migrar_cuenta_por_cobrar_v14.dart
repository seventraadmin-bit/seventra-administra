import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración aditiva de la Etapa 4J.1 (`schemaVersion` → 14): crea
/// `CuentaPorCobrar`/`CuentaPorCobrarEvento` y hace *backfill* — genera
/// una Cuenta por cobrar para cualquier `DocumentoPorEmitir` que ya
/// esté en `procesadoAceptado` sin una (Resolución F de Marlon,
/// explícita: "la migración debe generar automáticamente las Cuentas
/// por cobrar para cualquier Documento que ya esté en Procesado/
/// Aceptado. Hoy no tendrá efecto porque la base está vacía, pero es
/// la decisión correcta para instalaciones futuras").
///
/// Mismo snapshot y mismas reglas que la generación automática en
/// tiempo real (`DocumentoPorEmitirRepositoryImpl.cambiarEstatus`) —
/// deliberadamente reimplementado aquí con SQL/Drift directo, sin
/// importar clases de la capa de aplicación: mismo criterio que el
/// resto de las migraciones de este proyecto (`migrarServicioV6`,
/// `migrarDocumentoPorEmitirV12`, `migrarAttachmentV13` tampoco llaman
/// a ningún repositorio o caso de uso).
Future<void> migrarCuentaPorCobrarV14(AppDatabase db) async {
  await db.transaction(() async {
    final documentosAceptados = await (db.select(db.documentoPorEmitir)
          ..where((t) => t.estatus.equals('procesadoAceptado')))
        .get();

    for (final documento in documentosAceptados) {
      final yaExiste = await (db.select(db.cuentaPorCobrar)
            ..where((t) => t.documentoPorEmitirId.equals(documento.id)))
          .getSingleOrNull();
      if (yaExiste != null) continue;

      // `fechaEmisionReal`/`importeEmitido` son NOT NULL en
      // `DocumentoPorEmitir` desde el momento en que `RegistrarEmisionDocumentoPorEmitirUseCase`
      // los captura (Etapa 4I.2.1) — un documento no puede llegar a
      // `procesadoAceptado` sin haber pasado por `emitido` primero, así
      // que ambos campos siempre están presentes aquí.
      final cuenta = await db.into(db.cuentaPorCobrar).insertReturning(
            CuentaPorCobrarCompanion.insert(
              documentoPorEmitirId: documento.id,
              clienteId: documento.clienteId,
              tipoDocumento: documento.tipoDocumento,
              metodo: documento.metodo,
              requiereComplemento: Value(documento.requiereComplemento),
              folioDocumento: Value(documento.folioDocumento),
              serieFiscal: Value(documento.serieFiscal),
              folioFiscal: Value(documento.folioFiscal),
              uuid: Value(documento.uuid),
              fechaEmisionReal: documento.fechaEmisionReal!,
              importeEmitido: documento.importeEmitido!,
              saldoOriginal: documento.importeEmitido!,
              saldoPendiente: documento.importeEmitido!,
              fechaVencimiento: Value(documento.fechaPagoEsperadoProgramada),
            ),
          );

      await db.into(db.cuentaPorCobrarEvento).insert(
            CuentaPorCobrarEventoCompanion.insert(
              cuentaPorCobrarId: cuenta.id,
              fechaHora: DateTime.now(),
              tipoEvento: 'creada',
              estadoNuevo: const Value('pendiente'),
              observacion: const Value('Generada por backfill de migración (Etapa 4J.1).'),
            ),
          );
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración de CuentaPorCobrar a schemaVersion 14: foreign_key_check reportó '
        '${violacionesFk.length} violación(es) tras el backfill. Migración abortada.',
      );
    }
  });
}
