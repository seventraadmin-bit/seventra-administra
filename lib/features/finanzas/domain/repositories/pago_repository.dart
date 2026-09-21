import 'package:riseg_one/core/database/app_database.dart';

import '../usecases/eliminar_pago_fisicamente_usecase.dart';

/// Pagos y su aplicación a Cuentas por cobrar (Etapa 4J.2, modelo N:M
/// aprobado por Marlon) — `Pago` es el dinero recibido, nunca ligado a
/// una Cuenta específica; `AplicacionPago` es cuánto de ese dinero se
/// aplica a cada una. Nunca complementos CFDI ni conciliación
/// bancaria — eso pertenece a una etapa futura del dominio Finanzas.
abstract interface class PagoRepository {
  Future<PagoData?> obtenerPorId(String id);

  Future<AplicacionPagoData?> obtenerAplicacionPorId(String id);

  Future<List<PagoData>> listar({
    String? clienteId,
    String? estatus,
    String? formaPago,
    DateTime? rangoInicio,
    DateTime? rangoFin,
  });

  Future<List<AplicacionPagoData>> listarAplicacionesPorPago(String pagoId);

  Future<List<AplicacionPagoData>> listarAplicacionesPorCuenta(String cuentaPorCobrarId);

  /// TODAS las `AplicacionPago` con `estatus == aplicada` (universo
  /// pequeño esperado, mismo criterio que `CuentaPorCobrarRepository
  /// .listar()`/`ComplementoPagoRepository.listar()`) — una sola
  /// consulta para resolver "¿este Pago tiene Complemento pendiente?"
  /// sobre el listado completo, nunca una consulta por fila
  /// (`listarAplicacionesPorPago` es la variante N+1 que este método
  /// evita).
  Future<List<AplicacionPagoData>> listarTodasLasAplicacionesActivas();

  /// Historial administrativo del Pago en sí (registrado/corregido/
  /// cancelado/comprobanteAdjuntado) — el efecto de cada aplicación
  /// sobre una Cuenta específica vive en
  /// `CuentaPorCobrarRepository.listarEventos`, no aquí.
  Future<List<PagoEventoData>> listarEventos(String pagoId);

  /// Inserta el Pago (dinero recibido, sin aplicar a ninguna Cuenta
  /// todavía) y registra el evento `registrado`. `montoAplicado` nace
  /// en 0 siempre — un Pago sin aplicaciones es un estado válido
  /// (Resolución 8 de Marlon), no una excepción.
  Future<PagoData> crear({
    required String folioPago,
    String? clienteId,
    String? servicioEventualId,
    required int montoTotal,
    required DateTime fechaPago,
    required String formaPago,
    String? referencia,
    String? bancoOrigen,
    String? cuentaBancariaDestino,
    String? cuentaFinancieraId,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Aplica `monto` de un Pago ya existente a una Cuenta por cobrar:
  /// inserta la `AplicacionPago` (con `saldoAntes`/`saldoDespues`
  /// leídos en el momento), incrementa `Pago.montoAplicado`, decrementa
  /// `CuentaPorCobrar.saldoPendiente` y recalcula su `estatus`
  /// (pendiente/parcial/pagada), y registra el evento `pagoAplicado`
  /// en el historial de esa Cuenta — todo en una sola transacción. El
  /// llamador (caso de uso) ya validó sobrepago y que el Cliente del
  /// Pago coincide con el de la Cuenta.
  Future<AplicacionPagoData> aplicar({
    required String pagoId,
    required String cuentaPorCobrarId,
    required int monto,
    String? actorUsuarioId,
  });

  /// Crea el Pago y su única aplicación a [cuentaPorCobrarId] (con
  /// `monto = montoTotal`) en una sola transacción — el flujo
  /// simplificado que expone la interfaz de 4J.2. Internamente
  /// equivale a `crear` + `aplicar` compuestos atómicamente; existe
  /// como método propio (no dos llamadas separadas) para que un
  /// sobrepago rechazado nunca deje un Pago huérfano sin aplicaciones.
  Future<({PagoData pago, AplicacionPagoData aplicacion})> crearAplicado({
    required String folioPago,
    String? clienteId,
    String? servicioEventualId,
    required int montoTotal,
    required DateTime fechaPago,
    required String formaPago,
    required String cuentaPorCobrarId,
    String? referencia,
    String? bancoOrigen,
    String? cuentaBancariaDestino,
    String? cuentaFinancieraId,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Corrige un Pago — metadatos administrativos, y (Etapa 6, reversa
  /// explícita de la resolución anterior de Marlon) también
  /// `montoTotal`/`cuentaFinancieraId`/la distribución completa de
  /// `AplicacionPago`. El llamador (`CorregirPagoUseCase`) ya validó
  /// cada condición antes de llamar aquí (motivo, Complemento vigente,
  /// sobrepago, mismo Cliente) — este método solo ejecuta.
  ///
  /// [nuevaDistribucion] es el reemplazo COMPLETO de las aplicaciones
  /// activas de este Pago (nunca un delta): si se provee (incluso como
  /// lista vacía), primero se cancelan todas las `AplicacionPago`
  /// activas actuales (reutilizando [cancelarAplicacion] internamente)
  /// y luego se aplican las nuevas (reutilizando [aplicar]) — nunca se
  /// reduce/edita una aplicación existente in-place. `null` dejar las
  /// aplicaciones vigentes intactas (el monto total pudo cambiar sin
  /// tocar la distribución, dejando `pendientePorAplicar` distinto).
  ///
  /// [cuentaFinancieraId]/[limpiarCuentaFinancieraId]: `Pago` no tiene
  /// columna propia (la cuenta financiera vive únicamente en el
  /// `Ingreso` automático ligado) — cuando se provee, actualiza
  /// directamente `Ingreso.cuentaFinancieraId` en la misma transacción.
  ///
  /// Sincroniza el `Ingreso` automático ligado (monto/fecha/forma de
  /// pago/cuenta caja/cuenta financiera) — nunca lo deja desincronizado
  /// del Pago que le dio origen (hallazgo real de auditoría, Etapa 6).
  /// Registra `PagoEvento.corregido` (solo campos que cambiaron, más un
  /// resumen de la distribución si cambió — el detalle completo por
  /// Cuenta ya vive en `CuentaPorCobrarEvento`, vía `aplicar`/
  /// `cancelarAplicacion`, nunca duplicado aquí).
  Future<PagoData> corregir({
    required String pagoId,
    DateTime? fechaPago,
    String? formaPago,
    String? referencia,
    String? bancoOrigen,
    String? cuentaBancariaDestino,
    String? cuentaFinancieraId,
    bool limpiarCuentaFinancieraId = false,
    String? observaciones,
    int? montoTotal,
    List<({String cuentaPorCobrarId, int monto})>? nuevaDistribucion,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Cancela una aplicación individual: revierte su efecto sobre la
  /// Cuenta (`saldoPendiente`/`estatus`) y sobre `Pago.montoAplicado`
  /// (el dinero queda disponible para aplicarse de nuevo, a esa Cuenta
  /// o a otra), marca `estatus = cancelada` — nunca borra la fila
  /// (Resolución 6 de Marlon). No toca el Pago en sí.
  Future<AplicacionPagoData> cancelarAplicacion({
    required String aplicacionPagoId,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Cancela el Pago completo: cancela en cascada automáticamente
  /// todas sus aplicaciones vigentes (misma reversión que
  /// `cancelarAplicacion`, una por cada Cuenta afectada) y marca
  /// `Pago.estatus = cancelado` — nunca bloquea la cancelación por
  /// tener aplicaciones activas (Resolución 7 de Marlon: la primera
  /// opción, más amigable). Un Pago cancelado no admite nuevas
  /// aplicaciones.
  Future<PagoData> cancelar({
    required String pagoId,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Adjunta un comprobante de pago (Etapa 4J.2) — mismo mecanismo que
  /// cualquier otro adjunto (`Attachment`), sin campo dedicado dentro
  /// de `Pago`. Registra el evento `comprobanteAdjuntado`.
  Future<AttachmentData> adjuntarComprobante({
    required String pagoId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actorUsuarioId,
  });

  /// Elegibilidad de solo lectura para [eliminarFisicamente] — ver el
  /// doc comment de `ResumenEliminacionPago`.
  Future<ResumenEliminacionPago> obtenerResumenEliminacionFisica(String pagoId);

  /// Eliminación física extraordinaria (Etapa 15) — ver el doc comment
  /// completo en `PagoRepositoryImpl.eliminarFisicamente`.
  Future<EliminarPagoFisicamenteResultado> eliminarFisicamente({
    required String pagoId,
    required String motivo,
    String? actorUsuarioId,
  });
}
