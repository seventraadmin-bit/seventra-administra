import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart' show TipoDeuda;
import 'package:riseg_one/features/finanzas/domain/usecases/calcular_serie_disponibilidad_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_proyeccion_caja_usecase.dart' show OrigenCompromiso;
import 'package:riseg_one/features/reportes/domain/usecases/clasificar_egresos_por_origen_usecase.dart' show OrigenEgreso;
import 'package:riseg_one/features/reportes/reportes_providers.dart';

import '../../../organizacion/organizacion_providers.dart';
import '../../finanzas_providers.dart';
import '../cuentas_por_cobrar/cuentas_por_cobrar_resumen.dart';
import 'resumen_financiero_state.dart';
import 'package:riseg_one/features/finanzas/domain/contraparte_cobro.dart';

part 'resumen_financiero_controller.g.dart';

/// Controlador de la portada ejecutiva de Finanzas (Etapa 17) —
/// compone use cases ya existentes de Finanzas/Reportes, nunca
/// duplica su lógica. Regla crítica (pedido §11): "Por cobrar"/
/// "Vencido" son saldos AL DÍA DE HOY, siempre sobre el universo
/// completo de Cuentas por cobrar — el periodo seleccionado nunca las
/// filtra, solo afecta Ingresos/Egresos/Flujo neto y los feeds.
@riverpod
class ResumenFinancieroController extends _$ResumenFinancieroController {
  @override
  ResumenFinancieroState build() {
    Future.microtask(_cargar);
    return const ResumenFinancieroState();
  }

  /// Etapa 19B, hallazgo real (bug preexistente, expuesto por
  /// coincidencia de calendario): `DateTime(año, mes+1, 0)` da la
  /// MEDIANOCHE del último día del mes — cualquier movimiento
  /// capturado más tarde ese mismo día (la inmensa mayoría) quedaba
  /// fuera de "Este mes"/"Mes anterior" exactamente el último día de
  /// cada mes. Mismo criterio ya establecido en `PeriodoDashboard
  /// .finConHora`: se extiende el límite superior al final real del
  /// día (23:59:59.999).
  (DateTime, DateTime) _rangoDePeriodo(ResumenFinancieroState estado) {
    final hoy = DateTime.now();
    DateTime finConHora(DateTime fin) => DateTime(fin.year, fin.month, fin.day, 23, 59, 59, 999);
    return switch (estado.periodo) {
      PeriodoResumenFinanciero.esteMes => (DateTime(hoy.year, hoy.month, 1), finConHora(DateTime(hoy.year, hoy.month + 1, 0))),
      PeriodoResumenFinanciero.mesAnterior => (DateTime(hoy.year, hoy.month - 1, 1), finConHora(DateTime(hoy.year, hoy.month, 0))),
      PeriodoResumenFinanciero.personalizado => (
          estado.rangoPersonalizadoInicio ?? DateTime(hoy.year, hoy.month, 1),
          finConHora(estado.rangoPersonalizadoFin ?? hoy),
        ),
    };
  }

  /// Fecha límite de la Proyección de caja (Etapa 19C, Parte E) —
  /// siempre relativa a `hoy`, nunca al periodo del Resumen.
  DateTime _horizonteHasta(ResumenFinancieroState estado, DateTime hoy) {
    return switch (estado.horizonteProyeccion) {
      HorizonteProyeccion.dias7 => hoy.add(const Duration(days: 7)),
      HorizonteProyeccion.dias15 => hoy.add(const Duration(days: 15)),
      HorizonteProyeccion.dias30 => hoy.add(const Duration(days: 30)),
      HorizonteProyeccion.personalizado => estado.horizontePersonalizadoHasta ?? hoy.add(const Duration(days: 15)),
    };
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final (rangoInicio, rangoFin) = _rangoDePeriodo(state);
      final hoy = DateTime.now();

      final resumenFinanciero = await ref
          .read(obtenerResumenFinancieroUseCaseProvider)
          .ejecutar(rangoInicio: rangoInicio, rangoFin: rangoFin);

      // Saldo pendiente/vencido — universo COMPLETO de Cuentas por
      // cobrar, nunca acotado al periodo (regla crítica, ver doc del
      // controlador).
      final cuentasPorCobrar = await ref.read(cuentaPorCobrarRepositoryProvider).listar();
      final resumenCxC = calcularResumenCuentasPorCobrar(cuentasPorCobrar, hoy);

      // schemaVersion 88: los próximos cobros pueden ser de un eventual.
      final nombres = await ref.read(resolverNombresContraparteUseCaseProvider).paraCuentas(cuentasPorCobrar);

      final proximos = cuentasPorCobrar.where((c) => c.estatus != 'pagada' && c.fechaVencimiento != null).toList()
        ..sort((a, b) => a.fechaVencimiento!.compareTo(b.fechaVencimiento!));
      final proximosCobros = [
        for (final c in proximos.take(6))
          ProximoCobro(
            cuenta: c,
            clienteNombre: nombres.de(contraparteDeCuenta(c)),
          ),
      ];

      // Movimientos recientes — Ingreso/Egreso ya reconocidos del
      // periodo, unificados en memoria (nunca una tabla nueva).
      final ingresos = await ref
          .read(ingresoRepositoryProvider)
          .listar(estatus: 'registrado', rangoInicio: rangoInicio, rangoFin: rangoFin);
      final egresosConOrigen = await ref
          .read(clasificarEgresosPorOrigenUseCaseProvider)
          .ejecutar(rangoInicio: rangoInicio, rangoFin: rangoFin);

      // Deuda financiera — AL DÍA DE HOY, nunca acotada al periodo
      // (mismo criterio que "Por cobrar"/"Vencido" de CxC).
      final deudaFinancieraTotal = await ref.read(deudaRepositoryProvider).totalSaldoActivo();

      // Etapa 19B — cargos/pagos de tarjeta del periodo (informativo,
      // ver el doc comment de `ResumenFinancieroState`).
      final cargosTarjetaPeriodo =
          await ref.read(deudaRepositoryProvider).totalCargadoEnRango(rangoInicio: rangoInicio, rangoFin: rangoFin);
      final pagosTarjetaPeriodo = await ref
          .read(deudaRepositoryProvider)
          .totalPagadoEnRango(rangoInicio: rangoInicio, rangoFin: rangoFin, tipo: TipoDeuda.tarjetaCredito.name);

      // Etapa 19C, Parte A/D — posición de caja (saldo real derivado de
      // Cuentas financieras activas) y flujo de efectivo del periodo
      // (deliberadamente distinto de `resultadoOperativo`).
      final posicionDeCaja = await ref.read(obtenerPosicionDeCajaUseCaseProvider).ejecutar();
      final flujoEfectivoPeriodo =
          await ref.read(obtenerFlujoEfectivoUseCaseProvider).ejecutar(rangoInicio: rangoInicio, rangoFin: rangoFin);

      // Institución por cuenta — resuelta en lote (nunca un join por
      // fila), solo para las tarjetas de "Posición por cuenta".
      final bancos = await ref.read(catalogoRepositoryProvider).listarBancos();
      final nombrePorBancoId = {for (final b in bancos) b.id: b.nombre};
      final institucionNombrePorCuentaId = {
        for (final c in posicionDeCaja.cuentas)
          if (c.institucionId != null && nombrePorBancoId[c.institucionId] != null) c.id: nombrePorBancoId[c.institucionId]!,
      };

      // Etapa 19C, Parte E/F — proyección de caja al horizonte
      // seleccionado, siempre desde HOY (independiente del periodo de
      // arriba).
      final horizonteHasta = _horizonteHasta(state, hoy);
      final proyeccionCaja = await ref.read(obtenerProyeccionCajaUseCaseProvider).ejecutar(hoy: hoy, hasta: horizonteHasta);
      // Etapa 19D — "Deudas vencidas" ya NO se recalcula aquí: se deriva
      // de `proyeccionCaja.pendientesVencidos` (única fuente de verdad
      // de "vencido", compartida con Planeación financiera — nunca una
      // segunda lógica de vencidos).
      final deudasVencidasCount =
          proyeccionCaja.pendientesVencidos.where((p) => p.origen == OrigenCompromiso.deuda).length;
      // Etapa 19D — misma función pura que usa Planeación financiera,
      // solo para ubicar la fecha exacta del déficit en la alerta de
      // este Resumen (pedido §13: "basado en exactamente la misma
      // serie de Planeación").
      final serieDisponibilidad = proyeccionCaja.cuentasConfiguradas
          ? calcularSerieDisponibilidad(
              hoy: hoy,
              hasta: horizonteHasta,
              saldoActual: proyeccionCaja.saldoActual,
              compromisos: proyeccionCaja.compromisos,
            )
          : <PuntoDisponibilidadDiaria>[];

      final movimientos = <MovimientoFinanciero>[
        for (final i in ingresos)
          MovimientoFinanciero(
            fecha: i.fecha,
            concepto: i.concepto,
            origen: i.pagoId != null ? _origenPagoRecibido : _origenManual,
            importe: i.monto,
            tipo: TipoMovimientoFinanciero.ingreso,
          ),
        for (final ec in egresosConOrigen.detalle)
          MovimientoFinanciero(
            fecha: ec.egreso.fecha,
            concepto: ec.egreso.concepto,
            origen: switch (ec.origen) {
              OrigenEgreso.compra => _origenCompra,
              OrigenEgreso.nomina => _origenNomina,
              OrigenEgreso.tiempoExtra => _origenTiempoExtra,
              OrigenEgreso.deuda => _origenDeuda,
              OrigenEgreso.descuentoProgramado => _origenDescuentoProgramado,
              OrigenEgreso.vehiculo => _origenVehiculo,
              OrigenEgreso.telefonia => _origenTelefonia,
              OrigenEgreso.servicioEventual => _origenServicioEventual,
              OrigenEgreso.manual => _origenManual,
            },
            importe: ec.egreso.monto,
            tipo: TipoMovimientoFinanciero.egreso,
          ),
      ]..sort((a, b) => b.fecha.compareTo(a.fecha));

      state = state.copyWith(
        cargando: false,
        ingresosPeriodo: resumenFinanciero.totalIngresos,
        egresosPeriodo: resumenFinanciero.totalEgresos,
        egresosNomina: egresosConOrigen.totalNomina,
        egresosCompras: egresosConOrigen.totalCompra,
        egresosDeuda: egresosConOrigen.totalDeuda,
        // "Otros" agrupa Manual + Tiempo Extra + Descuento Programado
        // (préstamo) — este desglose no gana un bucket propio para no
        // rediseñar la pantalla; el origen real de cada Egreso sigue
        // siendo preciso en "Movimientos recientes" (ver el switch de
        // `origen` arriba, que sí distingue cada uno).
        egresosOtros: egresosConOrigen.totalManual + egresosConOrigen.totalTiempoExtra + egresosConOrigen.totalDescuentoProgramado,
        cargosTarjetaPeriodo: cargosTarjetaPeriodo,
        pagosTarjetaPeriodo: pagosTarjetaPeriodo,
        deudaFinancieraTotal: deudaFinancieraTotal,
        deudasVencidasCount: deudasVencidasCount,
        resumenCuentasPorCobrar: resumenCxC,
        movimientosRecientes: movimientos.take(8).toList(),
        proximosCobros: proximosCobros,
        posicionDeCaja: posicionDeCaja,
        institucionNombrePorCuentaId: institucionNombrePorCuentaId,
        flujoEfectivoPeriodo: flujoEfectivoPeriodo,
        proyeccionCaja: proyeccionCaja,
        serieDisponibilidad: serieDisponibilidad,
        errorCarga: null,
      );
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  static const _origenPagoRecibido = 'pagoRecibido';
  static const _origenManual = 'manual';
  static const _origenCompra = 'compra';
  static const _origenNomina = 'nomina';
  static const _origenTiempoExtra = 'tiempoExtra';
  static const _origenDeuda = 'deuda';
  static const _origenDescuentoProgramado = 'descuentoProgramado';
  static const _origenVehiculo = 'vehiculo';
  static const _origenTelefonia = 'telefonia';
  static const _origenServicioEventual = 'servicioEventual';

  Future<void> reintentarCarga() => _cargar();

  Future<void> cambiarPeriodo(PeriodoResumenFinanciero periodo) async {
    state = state.copyWith(periodo: periodo);
    await _cargar();
  }

  Future<void> aplicarRangoPersonalizado({required DateTime inicio, required DateTime fin}) async {
    state = state.copyWith(
      periodo: PeriodoResumenFinanciero.personalizado,
      rangoPersonalizadoInicio: inicio,
      rangoPersonalizadoFin: fin,
    );
    await _cargar();
  }

  Future<void> cambiarHorizonteProyeccion(HorizonteProyeccion horizonte) async {
    state = state.copyWith(horizonteProyeccion: horizonte);
    await _cargar();
  }

  Future<void> aplicarHorizontePersonalizado(DateTime hasta) async {
    state = state.copyWith(horizonteProyeccion: HorizonteProyeccion.personalizado, horizontePersonalizadoHasta: hasta);
    await _cargar();
  }
}
