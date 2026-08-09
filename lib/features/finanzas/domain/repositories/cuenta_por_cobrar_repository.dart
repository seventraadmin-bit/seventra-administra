import 'package:riseg_one/core/database/app_database.dart';

/// Cuentas por cobrar (Etapa 4J.1) — obligaciones de cobro reales,
/// generadas automáticamente cuando un `DocumentoPorEmitir` llega a
/// `procesadoAceptado`. Nunca pagos, complementos ni conciliación —
/// eso pertenece a una etapa futura del dominio Finanzas.
abstract interface class CuentaPorCobrarRepository {
  Future<CuentaPorCobrarData?> obtenerPorId(String id);

  /// `null` si el documento todavía no tiene Cuenta por cobrar — usado
  /// tanto para la idempotencia de la creación automática como para
  /// que el detalle de un `DocumentoPorEmitir` pueda enlazar a su
  /// Cuenta por cobrar cuando exista.
  Future<CuentaPorCobrarData?> obtenerPorDocumentoPorEmitirId(String documentoPorEmitirId);

  /// Inserta la Cuenta por cobrar (snapshot completo del documento) y
  /// registra el evento `creada`, en una sola transacción. El
  /// llamador (`DocumentoPorEmitirRepositoryImpl.cambiarEstatus`) ya
  /// validó que el documento está `procesadoAceptado` y que no existe
  /// una Cuenta por cobrar previa para él.
  Future<CuentaPorCobrarData> crear({
    required String documentoPorEmitirId,
    required String clienteId,
    required String tipoDocumento,
    required String metodo,
    required bool requiereComplemento,
    String? folioDocumento,
    String? serieFiscal,
    String? folioFiscal,
    String? uuid,
    required DateTime fechaEmisionReal,
    required int importeEmitido,
    DateTime? fechaVencimiento,
    String? actor,
  });

  /// `servicioId`/`entidadFiscalId` filtran vía join contra
  /// `DocumentoPorEmitirServicio`/`DocumentoPorEmitir` — la Cuenta por
  /// cobrar no denormaliza esos dos campos (Servicio no es 1:1 con un
  /// documento agrupado; Entidad fiscal ya vive en el documento de
  /// origen y no se pidió duplicarla).
  Future<List<CuentaPorCobrarData>> listar({
    String? clienteId,
    String? servicioId,
    String? entidadFiscalId,
    String? tipoDocumento,
    String? estatus,
    String? documentoPorEmitirId,
  });

  /// Completa o corrige `fechaVencimiento` — acción administrativa
  /// explícita (Resolución E de Marlon), nunca inventada al crear la
  /// cuenta. Registra el evento `fechaVencimientoDefinida` con el
  /// valor anterior/nuevo.
  Future<CuentaPorCobrarData> actualizarFechaVencimiento({
    required String cuentaPorCobrarId,
    required DateTime fechaVencimiento,
    String? motivo,
    String? actor,
  });

  /// Historial administrativo completo, en orden cronológico.
  Future<List<CuentaPorCobrarEventoData>> listarEventos(String cuentaPorCobrarId);
}
