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
    String? uuid,
    required DateTime fechaEmisionReal,
    required int importeEmitido,
    DateTime? fechaVencimiento,
    String? actorUsuarioId,
  });

  /// La Cuenta por cobrar de una venta eventual (schemaVersion 88) —
  /// método aparte de [crear] a propósito: el camino recurrente exige
  /// documento Y cliente, el eventual exige el eventual y admite
  /// cliente nulo. Meterlos en una sola firma con cuatro parámetros
  /// nullable haría que ninguna de las dos reglas se pudiera leer.
  ///
  /// [clienteId] se puebla sólo cuando el solicitante es un Cliente
  /// permanente; si no, la contraparte es el eventual mismo y se
  /// resuelve con `ContraparteCobro`.
  ///
  /// [fechaEmisionReal] es la fecha en que nació la obligación de
  /// cobro (la venta). Cuando el eventual se facture, el documento
  /// fiscal la refina vía [sincronizarConDocumentoFiscal] — nunca se
  /// inventa aquí un folio ni un UUID que todavía no existen.
  Future<CuentaPorCobrarData> crearDeServicioEventual({
    required String servicioEventualId,
    String? clienteId,
    required String tipoDocumento,
    required String metodo,
    required bool requiereComplemento,
    required DateTime fechaEmisionReal,
    required int importeEmitido,
    DateTime? fechaVencimiento,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// `null` si el eventual todavía no tiene Cuenta por cobrar — nunca
  /// debería ocurrir tras una creación exitosa (schemaVersion 88: todo
  /// eventual vendido tiene exactamente una), pero la lectura tiene
  /// que ser total para el histórico anterior a esta rebanada.
  Future<CuentaPorCobrarData?> obtenerPorServicioEventualId(String servicioEventualId);

  /// Las Cuentas de TODOS los eventuales pedidos, en una sola consulta
  /// — para que el listado de Eventuales muestre cobrado y pendiente
  /// sin una consulta por fila.
  Future<Map<String, CuentaPorCobrarData>> porServiciosEventuales(Iterable<String> servicioEventualIds);

  /// Copia a la Cuenta los datos fiscales del documento que se acaba
  /// de registrar/corregir: folio, UUID, fecha de emisión real, método
  /// y obligación de complemento. Es el único punto donde una CxC
  /// eventual cambia de `noAplica` a `pue`/`ppd`.
  ///
  /// Nunca toca saldo ni estatus: facturar no cobra.
  Future<CuentaPorCobrarData> sincronizarConDocumentoFiscal({
    required String cuentaPorCobrarId,
    String? folioDocumento,
    String? uuid,
    required DateTime fechaEmisionReal,
    required String metodo,
    required bool requiereComplemento,
    String? actorUsuarioId,
  });

  /// Corrige el importe de una CxC eventual cuyo eventual cambió de
  /// precio (schemaVersion 88). **Sólo** es alcanzable cuando la
  /// cuenta no tiene ninguna `AplicacionPago` activa — lo valida el
  /// caso de uso antes de llamar. Mantiene la invariante
  /// `saldoPendiente <= saldoOriginal` fijando los tres campos a la
  /// vez, y recalcula el estatus a `pendiente`.
  Future<CuentaPorCobrarData> corregirImporte({
    required String cuentaPorCobrarId,
    required int importeEmitido,
    required String motivo,
    String? actorUsuarioId,
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
    String? servicioEventualId,
  });

  /// Corrige campos administrativos de Categoría C (Etapa 7) —
  /// `fechaVencimiento`/`observaciones`, los únicos que son legítima
  /// propiedad de la CxC y no un snapshot congelado del Documento
  /// (`documentoPorEmitirId`/`clienteId`/.../`importeEmitido`/
  /// `saldoOriginal` NUNCA aceptan parámetro aquí — no existen). Nunca
  /// `saldoPendiente`/`estatus` (Categoría B, derivados, solo
  /// mutados por `PagoRepository.aplicar`/`cancelarAplicacion`/
  /// `corregir`). El llamador (`CorregirCuentaPorCobrarUseCase`) ya
  /// validó que la cuenta no está `cancelada` y que `motivo` es válido.
  /// Registra `corregida` vía `DiffEvento` (solo campos que
  /// cambiaron) — reemplaza `fechaVencimientoDefinida`, que queda
  /// legacy.
  Future<CuentaPorCobrarData> corregir({
    required String cuentaPorCobrarId,
    DateTime? fechaVencimiento,
    bool limpiarFechaVencimiento = false,
    String? observaciones,
    bool limpiarObservaciones = false,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Captura o corrige `fechaCobroReprogramada` (Etapa 19D) — nunca
  /// toca `fechaVencimiento` (la fecha contractual original permanece
  /// intacta). `null` en [fechaCobroReprogramada] limpia la
  /// reprogramación (la cuenta vuelve a "Pendientes vencidos" si sigue
  /// vencida) — mismo método reutilizado por
  /// `QuitarReprogramacionCobroCuentaPorCobrarUseCase`. Registra el
  /// evento `fechaCobroReprogramada` vía `DiffEvento`.
  Future<CuentaPorCobrarData> reprogramarCobro({
    required String cuentaPorCobrarId,
    required DateTime? fechaCobroReprogramada,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Cancela la obligación (Etapa 7) — nunca alcanzable si la cuenta
  /// tiene alguna `AplicacionPago` con `estatus == aplicada` (el
  /// llamador, `CancelarCuentaPorCobrarUseCase`, ya lo validó
  /// consultando `PagoRepository.listarAplicacionesPorCuenta`). Fija
  /// `estatus = cancelada` y `saldoPendiente = 0` (mismo criterio que
  /// `DescuentoProgramadoRepository.cancelarSaldo`: una obligación
  /// anulada no tiene nada pendiente que mostrar) — nunca toca
  /// `DocumentoPorEmitir` (decisión explícita: la dependencia
  /// Documento→CxC es de una sola vía, cancelar la CxC no propaga
  /// nada de vuelta). Registra el evento `cancelada`.
  Future<CuentaPorCobrarData> cancelar({
    required String cuentaPorCobrarId,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Historial administrativo completo, en orden cronológico.
  Future<List<CuentaPorCobrarEventoData>> listarEventos(String cuentaPorCobrarId);
}
