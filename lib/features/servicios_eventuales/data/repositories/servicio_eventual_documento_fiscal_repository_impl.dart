import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_por_cobrar_repository.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart'
    show MetodoPagoCobro;

import '../../domain/repositories/servicio_eventual_documento_fiscal_repository.dart';
import '../../domain/repositories/servicio_eventual_repository.dart';
import '../tables/servicio_eventual_documento_fiscal_table.dart';
import '../tables/servicio_eventual_table.dart';

class ServicioEventualDocumentoFiscalRepositoryImpl implements ServicioEventualDocumentoFiscalRepository {
  ServicioEventualDocumentoFiscalRepositoryImpl(
    this._db,
    this._cuentaPorCobrarRepository,
    this._servicioEventualRepository,
  );

  final AppDatabase _db;
  final CuentaPorCobrarRepository _cuentaPorCobrarRepository;

  /// Sólo para asentar el hecho comercial en la bitácora del eventual —
  /// el documento fiscal tiene además su propia historia en la CxC.
  final ServicioEventualRepository _servicioEventualRepository;

  @override
  Future<ServicioEventualDocumentoFiscalData?> obtenerPorId(String id) {
    return (_db.select(_db.servicioEventualDocumentoFiscal)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<ServicioEventualDocumentoFiscalData?> obtenerVigente(String servicioEventualId) {
    return (_db.select(_db.servicioEventualDocumentoFiscal)
          ..where((t) =>
              t.servicioEventualId.equals(servicioEventualId) &
              t.estatus.equals(EstatusDocumentoFiscalEventual.registrado.name)))
        .getSingleOrNull();
  }

  @override
  Future<List<ServicioEventualDocumentoFiscalData>> listarPorEventual(String servicioEventualId) {
    return (_db.select(_db.servicioEventualDocumentoFiscal)
          ..where((t) => t.servicioEventualId.equals(servicioEventualId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  @override
  Future<ServicioEventualDocumentoFiscalData> registrar({
    required String servicioEventualId,
    required String folio,
    String? uuid,
    required DateTime fechaEmision,
    required int importe,
    required String metodo,
    required bool requiereComplemento,
    required String snapshotRazonSocial,
    String? snapshotCodigoPostalFiscal,
    required String snapshotRfc,
    String? entidadFiscalId,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final documento = await _db.into(_db.servicioEventualDocumentoFiscal).insertReturning(
            ServicioEventualDocumentoFiscalCompanion.insert(
              servicioEventualId: servicioEventualId,
              folio: folio,
              uuid: Value(uuid),
              fechaEmision: fechaEmision,
              importe: importe,
              metodo: metodo,
              requiereComplemento: Value(requiereComplemento),
              snapshotRazonSocial: snapshotRazonSocial,
              snapshotCodigoPostalFiscal: Value(snapshotCodigoPostalFiscal),
              snapshotRfc: snapshotRfc,
              entidadFiscalId: Value(entidadFiscalId),
              observaciones: Value(observaciones),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );

      await _sincronizarCuenta(
        servicioEventualId: servicioEventualId,
        folioDocumento: folio,
        uuid: uuid,
        fechaEmision: fechaEmision,
        metodo: metodo,
        requiereComplemento: requiereComplemento,
        actorUsuarioId: actorUsuarioId,
      );

      await _servicioEventualRepository.registrarEvento(
        servicioEventualId: servicioEventualId,
        tipoEvento: TipoEventoServicioEventual.documentoFiscalRegistrado,
        observacion: 'Documento fiscal $folio',
        actorUsuarioId: actorUsuarioId,
      );

      return documento;
    });
  }

  @override
  Future<ServicioEventualDocumentoFiscalData> corregir({
    required String documentoId,
    String? folio,
    String? uuid,
    DateTime? fechaEmision,
    String? metodo,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final antes = (await obtenerPorId(documentoId))!;
      final metodoFinal = metodo ?? antes.metodo;
      final requiereComplementoFinal = MetodoPagoCobro.values.byName(metodoFinal) == MetodoPagoCobro.ppd;

      await (_db.update(_db.servicioEventualDocumentoFiscal)..where((t) => t.id.equals(documentoId))).write(
        ServicioEventualDocumentoFiscalCompanion(
          folio: folio == null ? const Value.absent() : Value(folio),
          uuid: Value(uuid),
          fechaEmision: fechaEmision == null ? const Value.absent() : Value(fechaEmision),
          metodo: Value(metodoFinal),
          requiereComplemento: Value(requiereComplementoFinal),
          observaciones: Value(observaciones),
          updatedAt: Value(DateTime.now()),
          actorUsuarioId: Value(actorUsuarioId),
        ),
      );
      final despues = (await obtenerPorId(documentoId))!;

      final diff = DiffEvento()
        ..anotar('folio', antes.folio, despues.folio)
        ..anotar('uuid', antes.uuid, despues.uuid)
        ..anotar('fechaEmision', antes.fechaEmision, despues.fechaEmision)
        ..anotar('metodo', antes.metodo, despues.metodo)
        ..anotar('requiereComplemento', antes.requiereComplemento, despues.requiereComplemento);

      // Sólo se vuelve a tocar la CxC si el documento VIGENTE cambió:
      // corregir un documento ya cancelado no debe reescribir cobranza.
      if (despues.estatus == EstatusDocumentoFiscalEventual.registrado.name) {
        await _sincronizarCuenta(
          servicioEventualId: despues.servicioEventualId,
          folioDocumento: despues.folio,
          uuid: despues.uuid,
          fechaEmision: despues.fechaEmision,
          metodo: despues.metodo,
          requiereComplemento: despues.requiereComplemento,
          actorUsuarioId: actorUsuarioId,
        );
      }

      if (diff.hayCambios) {
        await _servicioEventualRepository.registrarEvento(
          servicioEventualId: despues.servicioEventualId,
          tipoEvento: TipoEventoServicioEventual.documentoFiscalCorregido,
          observacion: motivo,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          actorUsuarioId: actorUsuarioId,
        );
      }

      return despues;
    });
  }

  @override
  Future<ServicioEventualDocumentoFiscalData> cancelar({
    required String documentoId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final antes = (await obtenerPorId(documentoId))!;

      await (_db.update(_db.servicioEventualDocumentoFiscal)..where((t) => t.id.equals(documentoId))).write(
        ServicioEventualDocumentoFiscalCompanion(
          estatus: Value(EstatusDocumentoFiscalEventual.cancelado.name),
          motivoCancelacion: Value(motivo),
          updatedAt: Value(DateTime.now()),
          actorUsuarioId: Value(actorUsuarioId),
        ),
      );

      // La CxC deja de citar un folio muerto, pero conserva el acuerdo
      // comercial: cancelar un CFDI mal timbrado no convierte una venta
      // PPD en PUE, y la obligación de Complemento del Pago ya recibido
      // sigue viva hasta que el sustituto la documente.
      await _sincronizarCuenta(
        servicioEventualId: antes.servicioEventualId,
        folioDocumento: null,
        uuid: null,
        fechaEmision: antes.fechaEmision,
        metodo: antes.metodo,
        requiereComplemento: antes.requiereComplemento,
        actorUsuarioId: actorUsuarioId,
      );

      await _servicioEventualRepository.registrarEvento(
        servicioEventualId: antes.servicioEventualId,
        tipoEvento: TipoEventoServicioEventual.documentoFiscalCancelado,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
      );

      return (await obtenerPorId(documentoId))!;
    });
  }

  Future<void> _sincronizarCuenta({
    required String servicioEventualId,
    required String? folioDocumento,
    required String? uuid,
    required DateTime fechaEmision,
    required String metodo,
    required bool requiereComplemento,
    String? actorUsuarioId,
  }) async {
    final cuenta = await _cuentaPorCobrarRepository.obtenerPorServicioEventualId(servicioEventualId);
    // El histórico anterior a la schemaVersion 88 puede no tener CxC;
    // un eventual nuevo siempre la tiene.
    if (cuenta == null) return;

    await _cuentaPorCobrarRepository.sincronizarConDocumentoFiscal(
      cuentaPorCobrarId: cuenta.id,
      folioDocumento: folioDocumento,
      uuid: uuid,
      fechaEmisionReal: fechaEmision,
      metodo: metodo,
      requiereComplemento: requiereComplemento,
      actorUsuarioId: actorUsuarioId,
    );
    await _servicioEventualRepository.registrarEvento(
      servicioEventualId: servicioEventualId,
      tipoEvento: TipoEventoServicioEventual.cuentaPorCobrarSincronizada,
      observacion: folioDocumento == null
          ? 'La cuenta por cobrar quedó sin documento fiscal vigente'
          : 'Cuenta por cobrar sincronizada con $folioDocumento',
      actorUsuarioId: actorUsuarioId,
    );
  }

  @override
  Future<AttachmentData> adjuntarArchivo({
    required String documentoId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final adjunto = await _db.into(_db.attachment).insertReturning(
            AttachmentCompanion.insert(
              id: const Uuid().v4(),
              categoria: const Value('documentoFiscalEventual'),
              originalFileName: originalFileName,
              storedFileName: storedFileName,
              path: path,
              mimeType: mimeType,
              sizeBytes: sizeBytes,
            ),
          );
      await _db.into(_db.servicioEventualDocumentoFiscalAttachment).insert(
            ServicioEventualDocumentoFiscalAttachmentCompanion.insert(
              attachmentId: adjunto.id,
              servicioEventualDocumentoFiscalId: documentoId,
            ),
          );
      return adjunto;
    });
  }

  @override
  Future<List<AttachmentData>> listarAdjuntos(String documentoId) async {
    final filas = await (_db.select(_db.servicioEventualDocumentoFiscalAttachment)
          ..where((t) => t.servicioEventualDocumentoFiscalId.equals(documentoId)))
        .get();
    if (filas.isEmpty) return const [];
    final ids = [for (final f in filas) f.attachmentId];
    return (_db.select(_db.attachment)..where((t) => t.id.isIn(ids))).get();
  }
}
