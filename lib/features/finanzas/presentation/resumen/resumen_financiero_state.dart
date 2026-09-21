import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/calcular_serie_disponibilidad_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_flujo_efectivo_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_posicion_de_caja_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_proyeccion_caja_usecase.dart';

import '../cuentas_por_cobrar/cuentas_por_cobrar_resumen.dart';

/// Periodo del Resumen financiero (Etapa 17) — presets discretos
/// (mismo criterio de usabilidad que Agenda), nunca un rango libre por
/// defecto. "Personalizado" habilita los dos `RisegDateField`.
enum PeriodoResumenFinanciero { esteMes, mesAnterior, personalizado }

/// Horizonte de la Proyección de caja (Etapa 19C, Parte E) — selector
/// independiente del periodo de arriba (ese acota Ingresos/Egresos
/// YA reconocidos; este mira hacia adelante, siempre desde HOY).
enum HorizonteProyeccion { dias7, dias15, dias30, personalizado }

/// Un movimiento de dinero ya reconocido (Ingreso o Egreso) — vista
/// unificada solo para el feed "Movimientos recientes" (Etapa 17,
/// pedido §2): nunca una tabla nueva, se construye en memoria a partir
/// de `Ingreso`/`Egreso` ya cargados.
enum TipoMovimientoFinanciero { ingreso, egreso }

class MovimientoFinanciero {
  const MovimientoFinanciero({
    required this.fecha,
    required this.concepto,
    required this.origen,
    required this.importe,
    required this.tipo,
  });

  final DateTime fecha;
  final String concepto;
  final String origen;
  final int importe;
  final TipoMovimientoFinanciero tipo;
}

/// Una Cuenta por cobrar próxima a vencer, con el nombre de Cliente ya
/// resuelto en lote (Etapa 17) — para "Próximos cobros".
class ProximoCobro {
  const ProximoCobro({required this.cuenta, required this.clienteNombre});

  final CuentaPorCobrarData cuenta;
  final String clienteNombre;
}

class ResumenFinancieroState {
  const ResumenFinancieroState({
    this.cargando = true,
    this.errorCarga,
    this.periodo = PeriodoResumenFinanciero.esteMes,
    DateTime? rangoInicio,
    DateTime? rangoFin,
    this.rangoPersonalizadoInicio,
    this.rangoPersonalizadoFin,
    this.ingresosPeriodo = 0,
    this.egresosPeriodo = 0,
    this.egresosNomina = 0,
    this.egresosCompras = 0,
    this.egresosDeuda = 0,
    this.egresosOtros = 0,
    this.cargosTarjetaPeriodo = 0,
    this.pagosTarjetaPeriodo = 0,
    this.deudaFinancieraTotal = 0,
    this.deudasVencidasCount = 0,
    this.resumenCuentasPorCobrar = const CuentasPorCobrarResumen(saldoPendiente: 0, saldoVencido: 0, saldoPorVencer: 0, pagadas: 0),
    this.movimientosRecientes = const [],
    this.proximosCobros = const [],
    this.posicionDeCaja = const PosicionDeCaja(configurada: false, saldoDisponible: 0, saldosPorCuenta: {}, cuentas: []),
    this.institucionNombrePorCuentaId = const {},
    this.flujoEfectivoPeriodo = const FlujoEfectivo(entradas: 0, salidas: 0),
    this.horizonteProyeccion = HorizonteProyeccion.dias15,
    this.horizontePersonalizadoHasta,
    this.proyeccionCaja = const ProyeccionCaja(cuentasConfiguradas: false, saldoActual: 0, compromisos: [], pendientesVencidos: []),
    this.serieDisponibilidad = const [],
  })  : _rangoInicio = rangoInicio,
        _rangoFin = rangoFin;

  final bool cargando;
  final String? errorCarga;
  final PeriodoResumenFinanciero periodo;
  final DateTime? _rangoInicio;
  final DateTime? _rangoFin;

  /// Solo tienen valor cuando `periodo == personalizado` — el rango
  /// efectivo para `esteMes`/`mesAnterior` se recalcula siempre a
  /// partir de la fecha real, nunca se guarda por separado.
  final DateTime? rangoPersonalizadoInicio;
  final DateTime? rangoPersonalizadoFin;

  DateTime get rangoInicio => _rangoInicio ?? DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime get rangoFin => _rangoFin ?? DateTime(DateTime.now().year, DateTime.now().month + 1, 0);

  /// Ingresos/Egresos/Flujo — métricas de FLUJO, acotadas al periodo
  /// seleccionado. `flujoDespuesDeuda` (Etapa 19, renombrado desde
  /// `flujoNeto` — mismo valor exacto: matemáticamente ya representaba
  /// "ingresos menos cada egreso del periodo, incluidos pagos de
  /// deuda") es distinto de `resultadoOperativo`, que EXCLUYE los pagos
  /// de deuda de los egresos (pedido explícito: nunca contar un pago
  /// de deuda como si fuera gasto operativo).
  final int ingresosPeriodo;
  final int egresosPeriodo;
  int get flujoDespuesDeuda => ingresosPeriodo - egresosPeriodo;

  /// Desglose de Egresos del periodo por origen real (Etapa 17,
  /// reutiliza `ClasificarEgresosPorOrigenUseCase` de Reportes — nunca
  /// una segunda clasificación; `egresosDeuda` agregado en la Etapa 19).
  final int egresosNomina;
  final int egresosCompras;
  final int egresosDeuda;
  final int egresosOtros;

  /// Etapa 19B — suma de `MovimientoDeuda.cargoCompra` del periodo:
  /// gasto operativo de Compras pagadas con tarjeta, reconocido en el
  /// momento de comprar (nunca cuando la tarjeta se paga después, ese
  /// pago ya está contado en `egresosDeuda`). Informativo: "Compras
  /// financiadas con TDC del periodo".
  final int cargosTarjetaPeriodo;

  /// Etapa 19B — subconjunto de `egresosDeuda` cuyos pagos son
  /// específicamente de tarjetas (`Deuda.tipo == tarjetaCredito`),
  /// nunca de préstamo/financiamiento. Informativo: "Pagos de tarjetas
  /// del periodo".
  final int pagosTarjetaPeriodo;

  /// Egresos operativos reales — cada egreso del periodo menos los
  /// pagos de deuda (Etapa 19, Parte 6 del pedido: un pago de deuda
  /// nunca es gasto operativo) MÁS los cargos de tarjeta del periodo
  /// (Etapa 19B: una Compra con TDC no genera Egreso, así que sin este
  /// término su gasto jamás aparecería aquí).
  int get egresosOperativos => egresosPeriodo - egresosDeuda + cargosTarjetaPeriodo;

  /// `ingresos − egresos operativos` — nunca incluye pagos de deuda.
  int get resultadoOperativo => ingresosPeriodo - egresosOperativos;

  /// Saldo total de Deudas `activa` — AL DÍA DE HOY, nunca acotado al
  /// periodo seleccionado (mismo criterio que "Por cobrar"/"Vencido").
  final int deudaFinancieraTotal;

  /// Cuántas Deudas activas ya pasaron su `fechaVencimiento` con
  /// `saldoActual > 0` — Etapa 19C, Parte H (alerta puramente
  /// matemática, "vencida", nunca un índice inventado).
  final int deudasVencidasCount;

  /// Por cobrar/Vencido/Por vencer/Pagadas — métricas de SALDO
  /// (devengado, "a hoy"), deliberadamente INDEPENDIENTES del periodo
  /// seleccionado (pedido §11: nunca sumar CxC + Ingresos como si
  /// fueran el mismo dinero).
  final CuentasPorCobrarResumen resumenCuentasPorCobrar;

  final List<MovimientoFinanciero> movimientosRecientes;
  final List<ProximoCobro> proximosCobros;

  /// Etapa 19C, Parte A — `Saldo inicial + Entradas reales − Salidas
  /// reales` agregado sobre las Cuentas financieras activas.
  /// `configurada == false` cuando no hay ninguna — la pantalla debe
  /// decirlo honestamente (Parte J), nunca mostrar `$0.00` como si
  /// fuera un saldo real.
  final PosicionDeCaja posicionDeCaja;

  /// Nombre de la institución (`Banco`) por `CuentaFinanciera.id` —
  /// resuelto en lote (Etapa 19C), nunca un join por fila. Solo cubre
  /// cuentas de tipo banco con `institucionId` capturado.
  final Map<String, String> institucionNombrePorCuentaId;

  /// Etapa 19C, Parte D — "Flujo de efectivo" del periodo seleccionado
  /// (entradas/salidas REALES de caja) — deliberadamente distinto de
  /// `resultadoOperativo`: un pago de deuda es salida de caja pero
  /// nunca gasto operativo otra vez.
  final FlujoEfectivo flujoEfectivoPeriodo;

  /// Horizonte de la Proyección (Parte E) — independiente del periodo
  /// de arriba.
  final HorizonteProyeccion horizonteProyeccion;
  final DateTime? horizontePersonalizadoHasta;

  /// Etapa 19C, Parte E/F — `saldoDisponible(hoy) + entradasPrevistas −
  /// salidasComprometidas`, con el detalle de compromisos reales
  /// (nunca inventados) para la tabla "Próximos compromisos".
  final ProyeccionCaja proyeccionCaja;

  /// Serie diaria (Etapa 19D) — MISMA función pura
  /// (`calcularSerieDisponibilidad`) que consume Planeación financiera;
  /// aquí solo sirve para ubicar la fecha exacta del déficit/mínimo en
  /// la alerta de este Resumen — nunca se muestra como gráfica aparte.
  final List<PuntoDisponibilidadDiaria> serieDisponibilidad;

  PuntoDisponibilidadDiaria? get puntoMinimoProyectado => encontrarMinimo(serieDisponibilidad);

  ResumenFinancieroState copyWith({
    bool? cargando,
    String? errorCarga,
    PeriodoResumenFinanciero? periodo,
    DateTime? rangoInicio,
    DateTime? rangoFin,
    DateTime? rangoPersonalizadoInicio,
    DateTime? rangoPersonalizadoFin,
    int? ingresosPeriodo,
    int? egresosPeriodo,
    int? egresosNomina,
    int? egresosCompras,
    int? egresosDeuda,
    int? egresosOtros,
    int? cargosTarjetaPeriodo,
    int? pagosTarjetaPeriodo,
    int? deudaFinancieraTotal,
    int? deudasVencidasCount,
    CuentasPorCobrarResumen? resumenCuentasPorCobrar,
    List<MovimientoFinanciero>? movimientosRecientes,
    List<ProximoCobro>? proximosCobros,
    PosicionDeCaja? posicionDeCaja,
    Map<String, String>? institucionNombrePorCuentaId,
    FlujoEfectivo? flujoEfectivoPeriodo,
    HorizonteProyeccion? horizonteProyeccion,
    DateTime? horizontePersonalizadoHasta,
    ProyeccionCaja? proyeccionCaja,
    List<PuntoDisponibilidadDiaria>? serieDisponibilidad,
  }) {
    return ResumenFinancieroState(
      cargando: cargando ?? this.cargando,
      errorCarga: errorCarga,
      periodo: periodo ?? this.periodo,
      rangoInicio: rangoInicio ?? _rangoInicio,
      rangoFin: rangoFin ?? _rangoFin,
      rangoPersonalizadoInicio: rangoPersonalizadoInicio ?? this.rangoPersonalizadoInicio,
      rangoPersonalizadoFin: rangoPersonalizadoFin ?? this.rangoPersonalizadoFin,
      ingresosPeriodo: ingresosPeriodo ?? this.ingresosPeriodo,
      egresosPeriodo: egresosPeriodo ?? this.egresosPeriodo,
      egresosNomina: egresosNomina ?? this.egresosNomina,
      egresosCompras: egresosCompras ?? this.egresosCompras,
      egresosDeuda: egresosDeuda ?? this.egresosDeuda,
      egresosOtros: egresosOtros ?? this.egresosOtros,
      cargosTarjetaPeriodo: cargosTarjetaPeriodo ?? this.cargosTarjetaPeriodo,
      pagosTarjetaPeriodo: pagosTarjetaPeriodo ?? this.pagosTarjetaPeriodo,
      deudaFinancieraTotal: deudaFinancieraTotal ?? this.deudaFinancieraTotal,
      deudasVencidasCount: deudasVencidasCount ?? this.deudasVencidasCount,
      resumenCuentasPorCobrar: resumenCuentasPorCobrar ?? this.resumenCuentasPorCobrar,
      movimientosRecientes: movimientosRecientes ?? this.movimientosRecientes,
      proximosCobros: proximosCobros ?? this.proximosCobros,
      posicionDeCaja: posicionDeCaja ?? this.posicionDeCaja,
      institucionNombrePorCuentaId: institucionNombrePorCuentaId ?? this.institucionNombrePorCuentaId,
      flujoEfectivoPeriodo: flujoEfectivoPeriodo ?? this.flujoEfectivoPeriodo,
      horizonteProyeccion: horizonteProyeccion ?? this.horizonteProyeccion,
      horizontePersonalizadoHasta: horizontePersonalizadoHasta ?? this.horizontePersonalizadoHasta,
      proyeccionCaja: proyeccionCaja ?? this.proyeccionCaja,
      serieDisponibilidad: serieDisponibilidad ?? this.serieDisponibilidad,
    );
  }
}
