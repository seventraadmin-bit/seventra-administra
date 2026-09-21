import 'package:riseg_one/core/database/app_database.dart';

/// El documento fiscal de un Servicio Eventual (schemaVersion 88).
///
/// **RISEG ONE no timbra**: aquí sólo se registra lo que un sistema
/// externo ya emitió. Cada escritura sincroniza además la Cuenta por
/// cobrar del eventual, porque el folio, el UUID y el método son datos
/// que la cobranza necesita y que hasta ahora no existían.
abstract interface class ServicioEventualDocumentoFiscalRepository {
  Future<ServicioEventualDocumentoFiscalData?> obtenerPorId(String id);

  /// El documento VIGENTE del eventual — `null` si nunca se facturó o
  /// si el único que hubo se canceló y aún no tiene sustituto.
  Future<ServicioEventualDocumentoFiscalData?> obtenerVigente(String servicioEventualId);

  /// Todos, incluidos los cancelados: el histórico fiscal no se pierde
  /// nunca, es justamente para lo que existe el índice único parcial.
  Future<List<ServicioEventualDocumentoFiscalData>> listarPorEventual(String servicioEventualId);

  /// Inserta el documento, sincroniza la Cuenta por cobrar del eventual
  /// (folio/UUID/fecha/método/complemento) y asienta el evento — todo
  /// en una sola transacción. El caso de uso ya validó formato de UUID,
  /// coherencia del método y que no haya otro vigente.
  Future<ServicioEventualDocumentoFiscalData> registrar({
    required String servicioEventualId,
    required String folio,
    String? uuid,
    required DateTime fechaEmision,
    required int importe,
    required String metodo,
    required bool requiereComplemento,
    required String snapshotRazonSocial,
    /// CP fiscal congelado (schemaVersion 90). `null` sólo para el
    /// histórico, que nunca lo capturó.
    String? snapshotCodigoPostalFiscal,
    required String snapshotRfc,
    String? entidadFiscalId,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Corrige los datos del documento y vuelve a sincronizar la CxC.
  /// `motivo` siempre obligatorio: cambiar un dato fiscal no puede
  /// ocurrir en silencio.
  Future<ServicioEventualDocumentoFiscalData> corregir({
    required String documentoId,
    String? folio,
    String? uuid,
    DateTime? fechaEmision,
    String? metodo,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Cancela el documento **sin** tocar la Cuenta por cobrar ni ningún
  /// Pago: la deuda y el dinero son hechos independientes de que un
  /// CFDI se haya cancelado.
  ///
  /// La CxC sí deja de citar un folio muerto: `folioDocumento` y `uuid`
  /// se limpian. `metodo`/`requiereComplemento` se conservan — cancelar
  /// un CFDI mal timbrado no cambia el acuerdo comercial PUE/PPD, y el
  /// sustituto volverá a llenarlos.
  Future<ServicioEventualDocumentoFiscalData> cancelar({
    required String documentoId,
    required String motivo,
    String? actorUsuarioId,
  });

  Future<AttachmentData> adjuntarArchivo({
    required String documentoId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actorUsuarioId,
  });

  Future<List<AttachmentData>> listarAdjuntos(String documentoId);
}
