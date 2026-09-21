import 'package:riseg_one/core/database/app_database.dart';
import '../../data/tables/servicio_eventual_table.dart';
import '../usecases/eliminar_servicio_eventual_fisicamente_usecase.dart';

/// El cobro que se registra EN EL MISMO acto de vender (schemaVersion
/// 88) — `null` significa "se cobra después", no "no se cobra".
class CobroInmediatoServicioEventual {
  const CobroInmediatoServicioEventual({
    required this.monto,
    required this.fechaPago,
    required this.formaPago,
    this.cuentaFinancieraId,
    this.referencia,
    this.observaciones,
  });

  final int monto;
  final DateTime fechaPago;
  final String formaPago;
  final String? cuentaFinancieraId;
  final String? referencia;
  final String? observaciones;
}

/// Lo que produce vender un eventual: SIEMPRE el eventual y su Cuenta
/// por cobrar; el Pago sólo si se cobró en el acto.
typedef VentaServicioEventual = ({
  ServicioEventualData eventual,
  CuentaPorCobrarData cuenta,
  PagoData? pago,
});


/// Totales derivados de un eventual — **nunca persistidos**. Se
/// resuelven en lote (`SUM ... GROUP BY`), jamás con una consulta por
/// fila del listado.
class TotalesServicioEventual {
  const TotalesServicioEventual({
    this.coberturasProgramadas = 0,
    this.coberturasPagadas = 0,
    this.costosProgramados = 0,
    this.costosPagados = 0,
  });

  final int coberturasProgramadas;
  final int coberturasPagadas;
  final int costosProgramados;
  final int costosPagados;

  /// Lo que el evento va a costar si todo lo programado se paga.
  int get costoComprometido => coberturasProgramadas + coberturasPagadas + costosProgramados + costosPagados;

  /// Lo que YA salió de la caja o se cargó a una tarjeta.
  int get costoPagado => coberturasPagadas + costosPagados;
}

/// Un cobro de la venta y qué tan atado está a ella.
///
/// La distinción importa al anular: un Pago que sólo cubría este
/// eventual se cancela entero, y con él vuelven atrás su Ingreso y el
/// saldo de la cuenta bancaria. Uno que además cubría otras Cuentas por
/// cobrar **no** se puede cancelar entero sin revertir cobros ajenos:
/// ahí sólo se cancela su aplicación a esta venta, y el dinero sigue en
/// el banco porque de verdad entró.
class CobroDeVentaEventual {
  const CobroDeVentaEventual({
    required this.pago,
    required this.aplicacionId,
    required this.monto,
    required this.exclusivoDeEstaVenta,
  });

  final PagoData pago;

  /// La aplicación vigente que ata ese Pago a la Cuenta del eventual.
  final String aplicacionId;

  /// Lo aplicado a ESTA venta, que no siempre es el total del Pago.
  final int monto;

  /// `true` si el Pago no tiene ninguna otra aplicación vigente.
  final bool exclusivoDeEstaVenta;
}

/// El núcleo operativo de un Servicio Eventual (Rebanada 1).
///
/// **No incluye cobranza.** La Cuenta por cobrar del eventual llega en
/// la Rebanada 2: el esquema ya la admite (`CuentaPorCobrar
/// .servicioEventualId`), pero ninguna ruta de este repositorio la
/// crea todavía.
abstract interface class ServicioEventualRepository {
  Future<ServicioEventualData?> obtenerPorId(String id);

  Future<List<ServicioEventualData>> listar({String? estatus});

  /// Totales de TODOS los eventuales pedidos, en cuatro consultas
  /// agregadas — nunca una por eventual.
  Future<Map<String, TotalesServicioEventual>> totalesPorEventual(Iterable<String> servicioEventualIds);

  /// El folio `EVT-000001` lo genera el repositorio con
  /// `CodigoSecuenciaService`, nunca el llamador — mismo criterio que
  /// Tiempo Extra y Compra.
  ///
  /// **Vender crea cobranza** (schemaVersion 88): el eventual y su
  /// única `CuentaPorCobrar` nacen en la MISMA transacción, y con
  /// [cobroInmediato] también el `Pago`, su `AplicacionPago` y su
  /// `Ingreso`. Si cualquier paso falla, no queda ni eventual
  /// huérfano ni una UI afirmando que se cobró.
  ///
  /// [metodoCobro] es `noAplica` cuando el eventual no se factura, y
  /// `pue`/`ppd` cuando sí — se acuerda al vender, no al facturar.
  ///
  /// [tratamientoIva] (schemaVersion 89) decide qué significa
  /// `importeAcordado`. La Cuenta por cobrar SIEMPRE recibe el total
  /// derivado con `totalVentaEventual`, nunca el importe capturado.
  Future<VentaServicioEventual> crear({
    required String nombre,
    required DateTime fechaHoraInicio,
    required DateTime fechaHoraFin,
    String? ubicacion,
    String? notas,
    required int importeAcordado,
    required TipoSolicitanteServicioEventual tipoSolicitante,
    String? clienteId,
    String? solicitanteNombre,
    String? solicitanteContacto,
    String? solicitanteTelefono,
    String? solicitanteCorreo,
    /// Receptor fiscal (schemaVersion 90): la `EntidadFiscal` del
    /// Cliente, o el snapshot capturado para un solicitante ocasional.
    /// Exactamente uno de los dos, y sólo cuando hay factura.
    String? entidadFiscalId,
    String? solicitanteRazonSocial,
    String? solicitanteRfc,
    String? solicitanteCodigoPostalFiscal,
    required bool requiereFactura,
    required String tratamientoIva,
    required String metodoCobro,
    required bool requiereComplemento,
    DateTime? fechaVencimiento,
    CobroInmediatoServicioEventual? cobroInmediato,
    String? actorUsuarioId,
  });

  /// La Cuenta por cobrar del eventual — `null` sólo para el histórico
  /// anterior a la schemaVersion 88.
  Future<CuentaPorCobrarData?> obtenerCuentaPorCobrar(String servicioEventualId);

  /// Lo efectivamente cobrado y VIGENTE de cada eventual pedido, en
  /// una sola consulta agregada.
  ///
  /// Suma las `AplicacionPago` `aplicada` de Pagos no cancelados. NO
  /// se deriva de `saldoOriginal - saldoPendiente`: cancelar una Cuenta
  /// por cobrar pone su saldo en 0, y esa resta pasaría a afirmar que
  /// se cobró todo justo cuando no se cobró nada. Mismo criterio que
  /// "Pagado" en Deudas, que se deriva de los movimientos y nunca de
  /// una resta de saldos.
  Future<Map<String, int>> cobradoVigentePorEventual(Iterable<String> servicioEventualIds);

  /// Los cobros vigentes de la venta, con su grado de exclusividad.
  /// Sólo lectura: no revierte nada, sirve para poder decirle al
  /// usuario qué va a pasar ANTES de que confirme.
  Future<List<CobroDeVentaEventual>> cobrosDeLaVenta(String servicioEventualId);

  /// Anula la venta completa (schemaVersion 90), en UNA transacción:
  ///
  ///  1. cancela cada Pago exclusivo de esta venta —lo que arrastra su
  ///     `AplicacionPago`, su `Ingreso` y el saldo de la cuenta—;
  ///  2. cancela sólo la aplicación de los Pagos compartidos;
  ///  3. cancela la Cuenta por cobrar, que queda sin saldo;
  ///  4. cancela el evento y lo que todavía no ocurrió.
  ///
  /// **Nunca toca un gasto real ya ejecutado.** Las coberturas y los
  /// costos ya pagados siguen pagados: ese dinero salió de verdad, y
  /// que el cliente ya no pague no se lo devuelve a nadie. Revertir un
  /// pago de cobertura es una decisión aparte y explícita.
  ///
  /// El llamador es responsable de haber comprobado los bloqueos
  /// fiscales (CFDI o Complemento vigentes) — ver
  /// `CancelarServicioEventualUseCase`.
  /// Sólo la mitad financiera de [anularVenta]: suelta los cobros
  /// (Pago exclusivo entero, o sólo la aplicación si es compartido) y
  /// cancela la Cuenta por cobrar. **No** toca el estatus del evento ni
  /// sus coberturas/costos.
  ///
  /// Existe para que la reconciliación de eventos cancelados antes de la
  /// v90 use exactamente el mismo código que la anulación nueva — el
  /// evento ya está cancelado, y volver a cancelarlo duplicaría el
  /// asiento en su historial.
  Future<void> revertirCobranzaDeLaVenta({
    required String servicioEventualId,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Eventos `cancelado` cuya Cuenta por cobrar NO está cancelada: la
  /// huella exacta de una cancelación hecha con la implementación
  /// anterior a la v90, que nunca revertía la cobranza.
  Future<List<ServicioEventualData>> listarCanceladosConCobranzaViva();

  Future<ServicioEventualData> anularVenta({
    required String servicioEventualId,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Nombre del solicitante externo de CADA eventual pedido, en una
  /// sola consulta. Es la mitad eventual de `nombreContraparte`: sin
  /// esto, una cobranza de solicitante ocasional se quedaría sin nombre
  /// en notificaciones, complementos, Dashboard y análisis de cobranza.
  ///
  /// Los eventuales de Cliente no aparecen aquí: su nombre lo resuelve
  /// `ClienteRepository`, que es la fuente correcta.
  Future<Map<String, String>> nombresSolicitantePorIds(Iterable<String> servicioEventualIds);

  Future<ServicioEventualData> corregir({
    required String servicioEventualId,
    String? nombre,
    String? tratamientoIva,
    DateTime? fechaHoraInicio,
    DateTime? fechaHoraFin,
    String? ubicacion,
    String? notas,
    int? importeAcordado,
    bool? requiereFactura,
    required String motivo,
    String? actorUsuarioId,
  });

  Future<ServicioEventualData> cambiarEstatus({
    required String servicioEventualId,
    required EstatusServicioEventual estatus,
    String? motivo,
    String? actorUsuarioId,
  });

  // --- Participantes ---------------------------------------------
  Future<List<ServicioEventualParticipanteData>> listarParticipantes(String servicioEventualId);

  Future<ServicioEventualParticipanteData> agregarParticipante({
    required String servicioEventualId,
    String? empleadoId,
    String? nombreExterno,
    String? telefonoExterno,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Sólo es posible mientras el participante no tenga ninguna
  /// cobertura — el llamador ya lo validó.
  Future<void> retirarParticipante({required String participanteId, String? actorUsuarioId});

  // --- Coberturas -------------------------------------------------
  Future<ServicioEventualCoberturaData?> obtenerCobertura(String coberturaId);

  Future<List<ServicioEventualCoberturaData>> listarCoberturas(String servicioEventualId);

  Future<List<ServicioEventualCoberturaData>> listarCoberturasPorParticipante(String participanteId);

  Future<ServicioEventualCoberturaData> agregarCobertura({
    required String servicioEventualId,
    required String participanteId,
    required DateTime fecha,
    required int horaInicioMinutos,
    required int horaFinMinutos,
    String? descripcionHorario,
    required int importeAcordado,
    String? actorUsuarioId,
  });

  Future<ServicioEventualCoberturaData> corregirCobertura({
    required String coberturaId,
    DateTime? fecha,
    int? horaInicioMinutos,
    int? horaFinMinutos,
    String? descripcionHorario,
    int? importeAcordado,
    required String motivo,
    String? actorUsuarioId,
  });

  Future<ServicioEventualCoberturaData> cancelarCobertura({
    required String coberturaId,
    required String motivo,
    String? actorUsuarioId,
  });

  /// El efecto financiero real: Cuenta → **exactamente un** Egreso;
  /// TDC → **exactamente un** `MovimientoDeuda` y cero Egresos. Todo
  /// en una transacción.
  Future<ServicioEventualCoberturaData> pagarCobertura({
    required String coberturaId,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaId,
    String? actorUsuarioId,
  });

  /// Revierte el pago **sin cancelar la cobertura**: vuelve a
  /// `programada` y puede volver a pagarse. Cancela el Egreso o
  /// revierte el cargo, exactamente una vez.
  Future<ServicioEventualCoberturaData> revertirPagoCobertura({
    required String coberturaId,
    required String motivo,
    String? actorUsuarioId,
  });

  // --- Costos ------------------------------------------------------
  Future<ServicioEventualCostoData?> obtenerCosto(String costoId);

  Future<List<ServicioEventualCostoData>> listarCostos(String servicioEventualId);

  Future<ServicioEventualCostoData> agregarCosto({
    required String servicioEventualId,
    required String concepto,
    required int monto,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  });

  Future<ServicioEventualCostoData> corregirCosto({
    required String costoId,
    String? concepto,
    int? monto,
    DateTime? fecha,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  });

  Future<ServicioEventualCostoData> cancelarCosto({
    required String costoId,
    required String motivo,
    String? actorUsuarioId,
  });

  Future<ServicioEventualCostoData> pagarCosto({
    required String costoId,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaId,
    String? actorUsuarioId,
  });

  Future<ServicioEventualCostoData> revertirPagoCosto({
    required String costoId,
    required String motivo,
    String? actorUsuarioId,
  });

  // --- Bitácora ----------------------------------------------------
  Future<void> registrarEvento({
    required String servicioEventualId,
    required TipoEventoServicioEventual tipoEvento,
    String? coberturaId,
    String? costoId,
    String? participanteId,
    String? observacion,
    String? estadoAnterior,
    String? estadoNuevo,
    String? actorUsuarioId,
  });

  Future<List<ServicioEventualEventoData>> listarEventos(String servicioEventualId);

  /// El eventual al que pertenece una cobertura/costo — para "Ver
  /// origen" desde Finanzas, siempre por FK real.
  Future<ServicioEventualCoberturaData?> obtenerCoberturaPorEgresoId(String egresoId);

  Future<ServicioEventualCostoData?> obtenerCostoPorEgresoId(String egresoId);

  /// TODOS los `egresoId` que este dominio ha generado — coberturas y
  /// costos juntos, en dos consultas fijas.
  ///
  /// Existe para `ClasificarEgresosPorOrigenUseCase`, que clasifica en
  /// memoria contra este conjunto: sin él, un Egreso de un eventual
  /// aparecería como "manual" en el desglose de Finanzas — el mismo
  /// hueco que ya tuvimos con Préstamos, Vehículos y Telefonía.
  Future<List<String>> listarEgresoIds();

  /// Eliminación física Maestro-only (Etapa 11D). Toda la validación
  /// de dependencias + el snapshot en `EliminacionFisicaEvento` + los
  /// `DELETE` ocurren transaccionalmente aquí; el caso de uso solo
  /// valida el motivo y traduce el resultado.
  Future<EliminarServicioEventualFisicamenteResultado> eliminarFisicamente({
    required String servicioEventualId,
    required String motivo,
    String? actorUsuarioId,
  });
}
