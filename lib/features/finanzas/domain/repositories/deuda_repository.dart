import 'package:riseg_one/core/database/app_database.dart';

/// Un cargo de tarjeta ya neteado, con la fecha en que reconocio el
/// gasto. [importeNeto] puede ser negativo: un ajusteNegativo que
/// revierte un cargo anterior resta gasto del periodo en que se
/// registro la correccion.
class CargoOperativoTarjeta {
  const CargoOperativoTarjeta({
    required this.deudaId,
    required this.fecha,
    required this.importeNeto,
    this.compraId,
    this.tiempoExtraId,
    this.costoAdicionalId,
    this.vehiculoMantenimientoId,
    this.egresoGastoId,
  });

  final String deudaId;
  final DateTime fecha;
  final int importeNeto;

  /// FK del hecho que origino el cargo — expuestas en crudo a
  /// proposito: quien clasifica el gasto por origen lo hace con la FK
  /// exacta, nunca adivinando por el texto del concepto. Un ajuste que
  /// corrige un cargo conserva la FK del cargo corregido, asi que la
  /// correccion se atribuye al mismo origen que el gasto original.
  final String? compraId;
  final String? tiempoExtraId;
  final int? costoAdicionalId;
  final String? vehiculoMantenimientoId;
  final String? egresoGastoId;
}

/// Resumen de solo lectura para el mensaje de confirmación dinámico de
/// "Eliminar físicamente" — mismo criterio que `ResumenEliminacionEgreso`/
/// `ResumenEliminacionCompra`. `detalleBloqueo` prácticamente nunca se
/// puebla en la práctica: `MovimientoDeuda` y los `Egreso` que genera
/// son propiedad exclusiva de su Deuda (nada externo los referencia,
/// a diferencia de `ArticuloUnidad` en Compra) — el campo existe por
/// consistencia de interfaz con el resto de dominios que comparten
/// `EliminacionFisicaEvento`.
class ResumenEliminacionDeuda {
  const ResumenEliminacionDeuda({required this.existe, this.detalleBloqueo});

  final bool existe;
  final String? detalleBloqueo;

  bool get bloqueado => detalleBloqueo != null;
}

/// Estado derivado de un pago individual (Etapa 9) — nunca persistido:
/// tanto "cancelado" como el importe neto se calculan a partir de los
/// movimientos vinculados por `MovimientoDeuda.movimientoOrigenId`, así
/// que la fila del pago original jamás se muta.
class EstadoPagoDeuda {
  const EstadoPagoDeuda({
    required this.existe,
    required this.cancelado,
    required this.importeNeto,
    required this.correcciones,
  });

  /// `false` también cuando el id existe pero no es un `tipo == pago`
  /// (ej. alguien pasó el id de un cargo) — el caso de uso lo traduce a
  /// un resultado tipado, nunca a una excepción cruda.
  final bool existe;

  final bool cancelado;

  /// Importe que este pago representa HOY: el capturado originalmente
  /// más/menos sus correcciones, y `0` si está cancelado. Es la cifra
  /// contra la que se valida un sobrepago al corregirlo.
  final int importeNeto;

  /// Cuántas correcciones de monto ha recibido — solo informativo para
  /// el expediente ("corregido 2 veces").
  final int correcciones;
}

/// Resultado de cancelar un pago (Etapa 9) — además de la Deuda ya
/// actualizada informa qué pasó con el ciclo de la tarjeta, para que la
/// UI pueda decirlo en voz alta en vez de dejarlo en silencio.
class CancelacionPagoDeuda {
  const CancelacionPagoDeuda({
    required this.deuda,
    required this.cicloTarjetaRetrocedido,
    required this.cicloTarjetaRequiereConciliacion,
  });

  final DeudaData deuda;

  /// `true` cuando el retroceso fue inequívoco y se aplicó.
  final bool cicloTarjetaRetrocedido;

  /// `true` cuando había un ciclo cubierto que este pago pudo haber
  /// avanzado, pero deshacerlo NO era inequívoco (hay pagos posteriores
  /// vivos, hubo conciliación manual después, o el pago es anterior a
  /// la Etapa 9 y no guardó el ancla previa). En ese caso el campo
  /// quedó intacto y el operador debe revisarlo desde "Corregir deuda".
  final bool cicloTarjetaRequiereConciliacion;
}

sealed class EliminarDeudaFisicamenteResultado {}

class EliminarDeudaFisicamenteExitoso extends EliminarDeudaFisicamenteResultado {}

class EliminarDeudaFisicamenteNoExiste extends EliminarDeudaFisicamenteResultado {}

class EliminarDeudaFisicamenteTieneDependencias extends EliminarDeudaFisicamenteResultado {
  EliminarDeudaFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

class EliminarDeudaFisicamenteErrorInesperado extends EliminarDeudaFisicamenteResultado {
  EliminarDeudaFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Una obligación financiera de la empresa (Etapa 19) — escritura
/// cruda, sin validaciones de negocio (existencia, estatus, montos);
/// esas viven en `RegistrarDeudaUseCase`/`RegistrarPagoDeudaUseCase`/
/// `CancelarDeudaUseCase`, mismo criterio que `AsignacionRepository`/
/// `CrearAsignacionUseCase`. Compone `EgresoRepository` real para cada
/// pago — nunca escribe directo sobre `_db.egreso`, mismo criterio que
/// `CompraRepositoryImpl`/`PagoNominaRepositoryImpl`.
abstract interface class DeudaRepository {
  Future<DeudaData?> obtenerPorId(String id);

  Future<List<DeudaData>> listar({String? tipo, String? estatus, String? busqueda});

  Future<List<MovimientoDeudaData>> listarMovimientos(String deudaId);

  /// Suma de `saldoActual` de Deudas `activa` — AL DÍA DE HOY, nunca
  /// acotado a un periodo (mismo criterio que "Por cobrar"/"Vencido" de
  /// Cuentas por cobrar).
  Future<int> totalSaldoActivo();

  /// `egresoId` de cada `MovimientoDeuda` tipo `pago` cuya `fecha` cae
  /// en el rango — insumo de `ClasificarEgresosPorOrigenUseCase` para
  /// que un pago de deuda nunca se cuente también como gasto operativo.
  Future<List<String>> listarEgresoIdsDePagosEnRango({DateTime? rangoInicio, DateTime? rangoFin});

  /// Resuelve la Deuda dueña de un `Egreso` puntual — busca el
  /// `MovimientoDeuda` tipo `pago` cuyo `egresoId` coincide (la única FK
  /// real; un cargo — `tipo == cargoCompra` — nunca tiene `egresoId`,
  /// ver el doc comment de `MovimientoDeuda`) — `null` si ese Egreso no
  /// vino de ningún pago de Deuda. Usado por el bloqueo de corrección/
  /// cancelación directa de Egreso (Etapa "Ingresos y Egresos") y por
  /// la navegación "Ver origen" desde su expediente.
  Future<String?> obtenerDeudaIdPorEgresoDePago(String egresoId);

  /// Suma de `importe` de `MovimientoDeuda` tipo `pago`, agrupada por
  /// `deudaId` — "Pagado" se deriva SIEMPRE de aquí (nunca de
  /// `importeOriginal - saldoActual`): esa resta deja de significar
  /// "lo pagado" en cuanto exista un `ajustePositivo`/`ajusteNegativo`
  /// (Etapa 19B). Sin `deudaIds`, agrega sobre todas las Deudas — una
  /// sola consulta para el listado completo, nunca N+1 por fila.
  Future<Map<String, int>> totalPagadoPorDeuda({List<String>? deudaIds});

  /// Etapa 19B — gasto NETO cargado a tarjetas cuya `fecha` cae en el
  /// rango: `cargoCompra` más `ajustePositivo`, menos `ajusteNegativo`
  /// (mismo criterio de neteo que [netoAportadoPorCompra]). Es el gasto
  /// operativo que un gasto pagado con tarjeta reconoce en el momento
  /// de incurrirlo (nunca al pagar la tarjeta después) — insumo de
  /// `ResumenFinancieroState.egresosOperativos` y de la cifra
  /// informativa "Gastos financiados con TDC del periodo". Nunca filtra
  /// por origen: cuenta igual venga de una Compra, un Tiempo Extra o un
  /// Egreso manual.
  ///
  /// Los ajustes se netean desde la Etapa "Origen financiero de Egresos
  /// manuales" — antes solo sumaba `cargoCompra`, así que revertir o
  /// reducir un cargo dejaba el gasto original contado íntegro en el
  /// Resultado operativo (bug real, ver el comentario de la
  /// implementación).
  Future<int> totalCargadoEnRango({DateTime? rangoInicio, DateTime? rangoFin});

  /// Los mismos cargos que suma [totalCargadoEnRango], pero uno por uno
  /// y con su fecha — insumo de la gráfica temporal de Reportes.
  ///
  /// Existe para que la serie y el KPI NO puedan diferir: la
  /// implementación de [totalCargadoEnRango] es exactamente un fold
  /// sobre esta lista, no una segunda consulta con su propio predicado.
  /// Esa duplicación es justo la que produce 'KPI dice 100,000 y la
  /// grafica 97,000'.
  Future<List<CargoOperativoTarjeta>> listarCargosEnRango({DateTime? rangoInicio, DateTime? rangoFin});

  /// Etapa 19B — igual que [listarEgresoIdsDePagosEnRango] pero
  /// filtrado a Deudas de un `tipo` puntual (ej. solo `tarjetaCredito`,
  /// para la cifra informativa "Pagos de tarjetas del periodo" — nunca
  /// mezclada con pagos de préstamo/financiamiento).
  Future<int> totalPagadoEnRango({DateTime? rangoInicio, DateTime? rangoFin, String? tipo});

  /// Etapa 19B — Deudas `tipo == tarjetaCredito` y `estatus == activa`,
  /// para el selector de "Tarjeta de crédito empresarial" en Registrar
  /// Compra. Nunca incluye canceladas/liquidadas/de otro tipo.
  Future<List<DeudaData>> listarTarjetasActivas();

  /// Etapa 19B — resuelve varias Deudas por id de una sola vez (mismo
  /// criterio que `CompraRepository.calcularTotalesPorCompra`: evita
  /// N+1 en el listado de Compras al mostrar la tarjeta que financió
  /// cada una).
  Future<Map<String, DeudaData>> listarPorIds(Iterable<String> ids);

  /// [fechaOrigen]/[importeOriginal] son obligatorios (validado en
  /// `RegistrarDeudaUseCase`, nunca aquí) solo para deuda fija — para
  /// `tipo == tarjetaCredito` pueden ser `null` (una línea revolvente no
  /// tiene "importe original" y su fecha de apertura puede no
  /// conocerse). [fechaSaldoInicial] es la fecha real del saldo de
  /// apertura capturado (`saldoInicial`) — puebla
  /// `MovimientoDeuda.altaInicial.fecha` con prioridad sobre
  /// [fechaOrigen] (`fechaSaldoInicial ?? fechaOrigen ?? DateTime.now()`),
  /// porque para una tarjeta que ya existía antes de RISEG ONE ambas
  /// fechas son distintas por diseño.
  Future<DeudaData> crear({
    required String folio,
    required String nombre,
    required String tipo,
    String? acreedor,
    DateTime? fechaOrigen,
    int? importeOriginal,
    required int saldoInicial,
    DateTime? fechaSaldoInicial,
    DateTime? fechaVencimiento,
    int? pagoProgramado,
    String? periodicidad,
    double? tasaInteres,
    String? referencia,
    String? observaciones,
    String? tarjetaUltimosDigitos,
    int? tarjetaLimiteCredito,
    int? tarjetaDiaCorte,
    int? tarjetaDiaPago,
    int? tarjetaPagoMinimo,
    String? tarjetaReglaFechaPago,
    int? tarjetaDiasDespuesCorte,
    String? tarjetaTipoTasa,
    String? tarjetaTasaReferencia,
    double? tarjetaTasaDiferencial,
    bool? tarjetaTasaMasIva,
    String? tarjetaTasaDescripcion,
    double? tarjetaCat,
    bool? tarjetaCatIncluyeIva,

    /// Reconciliación de apertura (Etapa "ciclo de TDC") — cuando se
    /// da de alta una TDC que ya traía consigo un ciclo de pago
    /// cubierto ANTES de capturar sus saldos reales en RISEG ONE. Puro
    /// dato: nunca genera `Egreso`/`MovimientoDeuda`/toca
    /// `CuentaFinanciera` — el saldo inicial capturado ya incorpora ese
    /// pago histórico.
    DateTime? tarjetaVencimientoCubiertoHasta,
    String? actorUsuarioId,
  });

  /// Metadata pura — nunca toca `tipo`/`importeOriginal`/`saldoActual`/
  /// `saldoInicial`/`fechaSaldoInicial`/`estatus` (todos inmutables
  /// post-alta).
  Future<DeudaData> corregir({
    required String deudaId,
    String? nombre,
    String? acreedor,
    DateTime? fechaOrigen,
    bool limpiarFechaOrigen = false,
    DateTime? fechaVencimiento,
    bool limpiarFechaVencimiento = false,
    int? pagoProgramado,
    bool limpiarPagoProgramado = false,
    String? periodicidad,
    bool limpiarPeriodicidad = false,
    double? tasaInteres,
    bool limpiarTasaInteres = false,
    String? referencia,
    String? observaciones,
    String? tarjetaUltimosDigitos,
    int? tarjetaLimiteCredito,
    int? tarjetaDiaCorte,
    int? tarjetaDiaPago,
    int? tarjetaPagoMinimo,
    String? tarjetaReglaFechaPago,
    int? tarjetaDiasDespuesCorte,
    String? tarjetaTipoTasa,
    bool limpiarTarjetaTipoTasa = false,
    String? tarjetaTasaReferencia,
    double? tarjetaTasaDiferencial,
    bool? tarjetaTasaMasIva,
    String? tarjetaTasaDescripcion,
    /// Limpia `tarjetaTasaReferencia`/`Diferencial`/`MasIva`/
    /// `Descripcion` como un solo grupo — siempre cambian juntos al
    /// cambiar de tipo de tasa, nunca uno sin los otros 3.
    bool limpiarTasaVariable = false,
    double? tarjetaCat,
    bool? tarjetaCatIncluyeIva,
    bool limpiarCat = false,

    /// Mismo campo/mismo criterio que en [crear] — puede corregirse o
    /// limpiarse después del alta (ej. si se marcó por error), nunca
    /// genera efectos secundarios financieros por sí solo.
    DateTime? tarjetaVencimientoCubiertoHasta,
    bool limpiarTarjetaVencimientoCubierto = false,
  });

  /// Crea el `Egreso` del pago + el `MovimientoDeuda` + actualiza
  /// `saldoActual`/`estatus` (→ `liquidada` si llega a 0) — una
  /// transacción. Asume que el llamador ya validó `importe > 0` y
  /// `importe <= saldoActual`, y ya generó [folioEgreso] (mismo
  /// criterio que `PagoRepository.crearAplicado(folioPago: ...)`: el
  /// folio se genera en el caso de uso, nunca dentro del repositorio).
  Future<DeudaData> registrarPago({
    required String deudaId,
    required String folioEgreso,
    required DateTime fecha,
    required int importe,
    required String formaPago,
    String? cuentaCaja,
    String? cuentaFinancieraId,
    String? referencia,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Un `MovimientoDeuda` puntual por su id — la identidad real de un
  /// pago individual (Etapa 9). `MovimientoDeuda.id` es autoincremental
  /// y único, así que basta por sí solo: nunca se identifica un pago
  /// por monto, fecha, texto ni "el último movimiento", y no hizo falta
  /// una entidad `PagoDeuda` aparte.
  Future<MovimientoDeudaData?> obtenerMovimiento(int movimientoId);

  /// Movimientos que corrigen o revierten [pagoId], por
  /// `movimientoOrigenId` — la trazabilidad completa de un pago para el
  /// expediente.
  Future<List<MovimientoDeudaData>> listarMovimientosDePago(int pagoId);

  /// Estado derivado de un pago: si existe, si está cancelado, su
  /// importe neto de hoy y cuántas correcciones acumula. Ver
  /// [EstadoPagoDeuda].
  Future<EstadoPagoDeuda> obtenerEstadoPago(int pagoId);

  /// Etapa 9 — corrige un pago ya registrado: su monto, su
  /// `CuentaFinanciera`, o ambos, en UNA transacción.
  ///
  /// Ledger append-only: la fila del pago original NUNCA se reescribe.
  /// La diferencia de monto entra como `ajustePositivo` (se pagó menos,
  /// la deuda vuelve a subir) o `ajusteNegativo` (se pagó más),
  /// vinculado con `movimientoOrigenId` — el historial conserva íntegro
  /// lo que se capturó por error, que es justo lo que pide la auditoría.
  ///
  /// El `Egreso` del pago se sincroniza siempre para representar la
  /// MISMA realidad (mismo id y folio, nunca se cancela y recrea):
  /// `corregirMonto` para el importe y `corregir` para la cuenta. Son
  /// llamadas internas de composición, así que no chocan con el bloqueo
  /// que `CorregirEgresoUseCase` impone desde Finanzas sobre ese mismo
  /// Egreso — mismo criterio que Compra/TiempoExtra con el suyo.
  ///
  /// Cambiar SOLO la cuenta no mueve el saldo de la Deuda: el pago
  /// lógico es el mismo, solo salió de otro banco. Escritura cruda:
  /// asume que el llamador (`CorregirPagoDeudaUseCase`) ya validó
  /// existencia, estatus, motivo y sobrepago.
  Future<DeudaData> corregirPago({
    required int pagoId,
    int? nuevoImporte,
    String? nuevaCuentaFinancieraId,
    bool limpiarCuentaFinanciera = false,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Etapa 9 — cancela un pago individual: escribe un `reversionPago`
  /// por su neto vivo (la fila original nunca se borra ni se muta),
  /// devuelve el saldo a la Deuda, recalcula `activa`/`liquidada`,
  /// cancela su `Egreso` —con lo que Caja y bancos recupera el dinero—
  /// y, en una TDC, devuelve el crédito disponible.
  ///
  /// El ciclo (`tarjetaVencimientoCubiertoHasta`) retrocede ÚNICAMENTE
  /// cuando deshacerlo es inequívoco; si no, queda intacto y el
  /// resultado lo reporta para que la UI lo diga. Ver
  /// [CancelacionPagoDeuda] y la implementación para las condiciones
  /// exactas. Escritura cruda: asume que el llamador ya validó que el
  /// pago existe y no estaba cancelado (una segunda cancelación nunca
  /// debe llegar aquí).
  Future<CancelacionPagoDeuda> cancelarPago({
    required int pagoId,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Escribe el `MovimientoDeuda` tipo `cancelacion` (importe = saldo
  /// condonado), zera `saldoActual`, `estatus → cancelada`. Nunca borra
  /// historial ni genera Egreso.
  Future<DeudaData> cancelar({
    required String deudaId,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Etapa 19B — el cargo que una Compra pagada con tarjeta genera al
  /// registrarse: aumenta `saldoActual`, vincula `compraId` de forma
  /// determinista, **nunca** genera Egreso (el gasto operativo se
  /// reconoce aquí, no cuando se pague la tarjeta después — ver el doc
  /// comment de `TipoMovimientoDeuda`). Escritura cruda: asume que el
  /// llamador (`RegistrarCompraUseCase`) ya validó `tipo ==
  /// tarjetaCredito`, `estatus == activa` y `monto <= creditoDisponible`
  /// ANTES de tocar nada — mismo criterio que `registrarPago` asume
  /// `importe <= saldoActual` ya validado.
  Future<DeudaData> registrarCargoCompra({
    required String deudaId,
    required String compraId,
    required int monto,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Etapa "origen financiero unificado" — mismo mecanismo exacto que
  /// [registrarCargoCompra] (aumenta `saldoActual`, inserta
  /// `MovimientoDeuda.cargoCompra`, **nunca** genera Egreso), vinculado
  /// vía `tiempoExtraId` en vez de `compraId` — para cuando el PAGO
  /// BASE de una cobertura de Tiempo Extra se carga directo a la
  /// tarjeta. Asume que el llamador ya validó la tarjeta (existe,
  /// activa, límite suficiente vía `validarOrigenTarjeta`).
  Future<DeudaData> registrarCargoTiempoExtra({
    required String deudaId,
    required String tiempoExtraId,
    required int monto,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Igual que [registrarCargoTiempoExtra], pero para UN costo
  /// adicional específico de la cobertura (nunca el pago base) —
  /// vinculado vía `costoAdicionalId`.
  Future<DeudaData> registrarCargoCostoAdicional({
    required String deudaId,
    required int costoAdicionalId,
    required int monto,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Reversión de [registrarCargoTiempoExtra] — mismo mecanismo exacto
  /// que [revertirCargoCompra] (un `ajusteNegativo` por el neto
  /// aportado), usado al cancelar un Tiempo Extra cuyo pago base se
  /// cargó a tarjeta.
  Future<DeudaData> revertirCargoTiempoExtra({
    required String deudaId,
    required String tiempoExtraId,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Igual que [revertirCargoTiempoExtra], pero para un costo
  /// adicional específico.
  Future<DeudaData> revertirCargoCostoAdicional({
    required String deudaId,
    required int costoAdicionalId,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Neto aportado por un mantenimiento a esa tarjeta (cargo original
  /// más ajustes) — igual que [netoAportadoPorCompra].
  Future<int> netoAportadoPorMantenimientoVehiculo({
    required String deudaId,
    required String vehiculoMantenimientoId,
  });

  /// Etapa "Vehículos: ciclo de vida y origen financiero"
  /// (schemaVersion 80) — mismo mecanismo exacto que
  /// [registrarCargoCompra]/[registrarCargoTiempoExtra]: aumenta
  /// `saldoActual`, inserta un `cargoCompra` vinculado por FK real
  /// (`vehiculoMantenimientoId`) y **nunca** genera un Egreso. La salida
  /// de banco ocurre después, al pagar la tarjeta.
  ///
  /// Asume que el llamador ya validó la tarjeta con
  /// `validarOrigenTarjeta`.
  Future<DeudaData> registrarCargoMantenimientoVehiculo({
    required String deudaId,
    required String vehiculoMantenimientoId,
    required int monto,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Cargo de una RECARGA de línea telefónica pagada con tarjeta —
  /// mismo mecanismo exacto que [registrarCargoCompra]/
  /// [registrarCargoMantenimientoVehiculo]: aumenta `saldoActual`,
  /// inserta un cargo vinculado por FK real
  /// (`recargaLineaTelefonicaId`) y **nunca** genera un Egreso. La
  /// salida de banco ocurre después, al pagar la tarjeta.
  ///
  /// Asume que el llamador ya validó la tarjeta con
  /// `validarOrigenTarjeta`.
  Future<DeudaData> registrarCargoRecargaLineaTelefonica({
    required String deudaId,
    required String recargaLineaTelefonicaId,
    required int monto,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Reversión de [registrarCargoRecargaLineaTelefonica] — un
  /// `ajusteNegativo` por el NETO aportado por esa recarga a esa
  /// tarjeta. Idempotente por construcción: si el neto ya es 0 (porque
  /// se revirtió antes), no escribe nada — una segunda cancelación
  /// jamás produce una segunda reversión.
  Future<DeudaData> revertirCargoRecargaLineaTelefonica({
    required String deudaId,
    required String recargaLineaTelefonicaId,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Ajuste del cargo de una recarga que sigue en la MISMA tarjeta
  /// (corrección de importe) — un `ajustePositivo`/`ajusteNegativo`
  /// por el delta, nunca reescribe el cargo original.
  Future<DeudaData> registrarAjusteCargoRecargaLineaTelefonica({
    required String deudaId,
    required String recargaLineaTelefonicaId,
    required int deltaImporte,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Cargo de una COBERTURA de Servicio Eventual pagada con tarjeta
  /// (schemaVersion 87) — mismo mecanismo exacto que
  /// [registrarCargoCompra]/[registrarCargoRecargaLineaTelefonica]:
  /// aumenta `saldoActual`, inserta un `MovimientoDeuda` de tipo
  /// `cargo` con la FK inversa real y **nunca** genera un Egreso.
  ///
  /// Asume que el llamador ya validó la tarjeta con
  /// `validarOrigenTarjeta`.
  Future<DeudaData> registrarCargoCoberturaServicioEventual({
    required String deudaId,
    required String coberturaId,
    required int monto,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Reversión de [registrarCargoCoberturaServicioEventual] — un
  /// `ajusteNegativo` por el NETO aportado por esa cobertura a esa
  /// tarjeta. Idempotente: si el neto ya es 0, no escribe nada, así que
  /// revertir dos veces jamás devuelve el dinero dos veces.
  Future<DeudaData> revertirCargoCoberturaServicioEventual({
    required String deudaId,
    required String coberturaId,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Igual que [registrarCargoCoberturaServicioEventual] pero para un
  /// COSTO adicional del eventual — su propio cargo, nunca fusionado
  /// con el de una cobertura.
  Future<DeudaData> registrarCargoCostoServicioEventual({
    required String deudaId,
    required String costoId,
    required int monto,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Reversión de [registrarCargoCostoServicioEventual].
  Future<DeudaData> revertirCargoCostoServicioEventual({
    required String deudaId,
    required String costoId,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Reversión de [registrarCargoMantenimientoVehiculo] — un
  /// `ajusteNegativo` por el NETO aportado por ese mantenimiento a esa
  /// tarjeta. Idempotente por construcción: si el neto ya es 0 (porque
  /// se revirtió antes), no escribe nada — una segunda cancelación
  /// jamás produce una segunda reversión.
  Future<DeudaData> revertirCargoMantenimientoVehiculo({
    required String deudaId,
    required String vehiculoMantenimientoId,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Ajuste del cargo de un mantenimiento que sigue en la MISMA tarjeta
  /// (corrección de monto) — mismo mecanismo que el equivalente de
  /// Compra/Tiempo Extra: un `ajustePositivo`/`ajusteNegativo` por la
  /// diferencia, nunca reescribir el cargo original.
  Future<DeudaData> registrarAjusteCargoMantenimientoVehiculo({
    required String deudaId,
    required String vehiculoMantenimientoId,
    required int deltaImporte,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Etapa "Origen financiero de Egresos manuales: Cuenta vs. TDC" —
  /// mismo mecanismo exacto que [registrarCargoCompra]/
  /// [registrarCargoTiempoExtra] (aumenta `saldoActual`, inserta
  /// `MovimientoDeuda.cargoCompra`, **nunca** genera Egreso), vinculado
  /// vía `egresoGastoId`: el gasto manual que se financió con esta
  /// tarjeta en vez de con una `CuentaFinanciera`. A diferencia de los
  /// otros tres orígenes, el `Egreso` de [egresoId] YA EXISTE cuando se
  /// llama aquí — es el documento del gasto, no un subproducto del
  /// cargo. Escritura cruda: asume que el llamador
  /// (`RegistrarEgresoUseCase`/`CorregirEgresoUseCase`) ya validó la
  /// tarjeta con `validarOrigenTarjeta`.
  Future<DeudaData> registrarCargoEgreso({
    required String deudaId,
    required String egresoId,
    required int monto,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Igual que [registrarAjusteCargoCompra], vinculado vía
  /// `egresoGastoId` — para cuando el monto de un gasto manual
  /// financiado con TDC se corrige SIN cambiar de tarjeta (misma TDC,
  /// monto distinto). Nunca reescribe el cargo original.
  Future<DeudaData> registrarAjusteCargoEgreso({
    required String deudaId,
    required String egresoId,
    required int deltaImporte,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Igual que [revertirCargoCompra], vinculado vía `egresoGastoId` —
  /// un `ajusteNegativo` por el neto que ese gasto manual aporta hoy al
  /// saldo. Usado al cancelar el Egreso y al moverlo a otro origen
  /// (otra TDC o una CuentaFinanciera).
  Future<DeudaData> revertirCargoEgreso({
    required String deudaId,
    required String egresoId,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Igual que [netoAportadoPorCompra], para un gasto manual — el
  /// efecto NETO que [egresoId] aporta HOY al `saldoActual` de
  /// [deudaId]. Necesario para validar crédito disponible al corregir
  /// el monto EN LA MISMA tarjeta: el gasto ya ocupa parte de ese
  /// saldo y debe descontarse antes de comparar.
  Future<int> netoAportadoPorEgreso({required String deudaId, required String egresoId});

  /// Etapa 19B — corrige el cargo de una Compra cuyo total cambió:
  /// `deltaImporte > 0` escribe un `ajustePositivo`, `< 0` un
  /// `ajusteNegativo` (magnitud) — **nunca** reescribe el
  /// `MovimientoDeuda.cargoCompra` original (append-only real). Usado
  /// por `CompraRepository.corregir` en vez de `EgresoRepository
  /// .corregirMonto` cuando `Compra.deudaId != null`.
  Future<DeudaData> registrarAjusteCargoCompra({
    required String deudaId,
    required String compraId,
    required int deltaImporte,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Etapa 19B — revierte por completo el cargo de una Compra que se
  /// cancela: un `ajusteNegativo` por el importe neto que esa Compra
  /// aportó al saldo (cargo original ± ajustes previos), nunca menos.
  /// Usado por `CompraRepository.cancelar` en vez de `EgresoRepository
  /// .cancelar` cuando `Compra.deudaId != null`.
  Future<DeudaData> revertirCargoCompra({
    required String deudaId,
    required String compraId,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Etapa 3 (Compras — corrección financiera completa Cuenta↔TDC): el
  /// efecto NETO (cargo original ± ajustes) que [compraId] aporta HOY
  /// al `saldoActual` de [deudaId] — `0` si nunca tocó esta Deuda o si
  /// sus movimientos ya se cancelan entre sí. Necesario para validar
  /// crédito disponible de una corrección de monto EN LA MISMA
  /// tarjeta: comparar el monto nuevo contra el saldo total sería
  /// ingenuo — la propia Compra ya "ocupa" parte de ese saldo, y debe
  /// descontarse antes de validar (ver el doc comment de
  /// `CorregirCompraUseCase`).
  Future<int> netoAportadoPorCompra({required String deudaId, required String compraId});

  /// Etapa "corrección real de Tiempo Extra" — mismo mecanismo exacto
  /// que [registrarAjusteCargoCompra] (un `ajustePositivo`/
  /// `ajusteNegativo` por la DIFERENCIA, nunca reescribe el cargo
  /// original), vinculado vía `tiempoExtraId`. Usado por
  /// `TiempoExtraRepository.corregir` cuando el pago base se corrige
  /// SIN cambiar de tarjeta (misma TDC, monto distinto).
  Future<DeudaData> registrarAjusteCargoTiempoExtra({
    required String deudaId,
    required String tiempoExtraId,
    required int deltaImporte,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Igual que [registrarAjusteCargoTiempoExtra], para un costo
  /// adicional específico.
  Future<DeudaData> registrarAjusteCargoCostoAdicional({
    required String deudaId,
    required int costoAdicionalId,
    required int deltaImporte,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Etapa "corrección real de Tiempo Extra" — igual criterio que
  /// [detalleBloqueoEliminacionCargoCompra], evaluado a la vez sobre
  /// TODOS los movimientos de [tiempoExtraId] (pago base) y de cada id
  /// en [costoAdicionalIds] — pueden vivir en tarjetas distintas, cada
  /// una se verifica de forma independiente. Usado exclusivamente para
  /// eliminación física de un TiempoExtra ya cancelado.
  Future<String?> detalleBloqueoEliminacionCargoTiempoExtra({
    required String tiempoExtraId,
    required List<int> costoAdicionalIds,
  });

  /// Igual que [eliminarCargoCompraFisicamente], pero borra a la vez
  /// todos los movimientos de [tiempoExtraId] y de cada id en
  /// [costoAdicionalIds], restaurando el saldo de cada tarjeta
  /// involucrada de forma independiente. Llamar únicamente cuando
  /// [detalleBloqueoEliminacionCargoTiempoExtra] devolvió `null`.
  Future<void> eliminarCargoTiempoExtraFisicamente({
    required String tiempoExtraId,
    required List<int> costoAdicionalIds,
  });

  /// Etapa 19B — `null` si el/los `MovimientoDeuda` vinculados a
  /// [compraId] (cargo + cualquier ajuste posterior) son exactamente el
  /// final del historial de esa tarjeta (nada más se registró después,
  /// ni de esta ni de otra Compra) — en ese caso es seguro eliminarlos
  /// sin corromper el encadenamiento `saldoAnterior`/`saldoPosterior` de
  /// ningún otro movimiento. Mensaje de bloqueo explícito si no.
  Future<String?> detalleBloqueoEliminacionCargoCompra(String compraId);

  /// Etapa 19B — para eliminación física/de cadena de prueba de una
  /// Compra pagada con tarjeta: borra el/los `MovimientoDeuda`
  /// vinculados a [compraId] y restaura `saldoActual` de la tarjeta al
  /// valor previo a ese cargo. Llamar únicamente cuando
  /// [detalleBloqueoEliminacionCargoCompra] devolvió `null`, y ANTES de
  /// borrar la fila `Compra` (su FK es `restrict`).
  Future<void> eliminarCargoCompraFisicamente(String compraId);

  Future<ResumenEliminacionDeuda> obtenerResumenEliminacionFisica(String deudaId);

  /// Eliminación física extraordinaria (Maestro-only, vía
  /// `exigirMaestro` en el provider — nunca aquí). Snapshotea Deuda +
  /// todos sus `MovimientoDeuda` + los `Egreso` que generaron en
  /// `EliminacionFisicaEvento`, y borra todo el agregado sin dejar
  /// huérfanos.
  Future<EliminarDeudaFisicamenteResultado> eliminarFisicamente({
    required String deudaId,
    required String motivo,
    String? actorUsuarioId,
  });
}
