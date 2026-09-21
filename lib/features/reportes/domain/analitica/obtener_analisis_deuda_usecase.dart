import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/calcular_fecha_tarjeta_usecase.dart';

import 'comparacion_periodo.dart';

/// A qué hecho del negocio corresponde un movimiento de deuda.
///
/// Se resuelve SIEMPRE por FK (`compraId`, `tiempoExtraId`,
/// `costoAdicionalId`, `vehiculoMantenimientoId`, `egresoGastoId`),
/// nunca por el texto de la observación.
enum OrigenMovimientoDeuda { compra, tiempoExtra, costoAdicionalTiempoExtra, vehiculo, egreso, pago, apertura, sinOrigen }

/// Un movimiento de deuda con su tarjeta/deuda y su origen resuelto.
class MovimientoDeudaProyectado {
  const MovimientoDeudaProyectado({
    required this.movimiento,
    required this.deudaNombre,
    required this.deudaId,
    required this.tipo,
    required this.origen,
    required this.efectoEnSaldo,
  });

  final MovimientoDeudaData movimiento;
  final String deudaNombre;
  final String deudaId;
  final TipoMovimientoDeuda tipo;
  final OrigenMovimientoDeuda origen;

  /// Cuánto movió el saldo de la deuda, con signo: positivo lo aumenta,
  /// negativo lo reduce. El importe almacenado siempre es positivo; la
  /// dirección la da el tipo, nunca el signo (regla del dominio).
  final int efectoEnSaldo;

  DateTime get fecha => movimiento.fecha;
}

/// Una tarjeta con sus cifras de utilización y su ciclo.
class TarjetaProyectada {
  const TarjetaProyectada({
    required this.deuda,
    required this.disponible,
    required this.utilizacion,
    required this.proximoCorte,
    required this.proximaFechaLimite,
  });

  final DeudaData deuda;

  /// `null` cuando la tarjeta no tiene límite capturado — nunca se
  /// asume $0, que significaría "sin crédito".
  final int? disponible;

  /// Fracción del límite usada (0.72 == 72 %). `null` sin límite.
  final double? utilizacion;

  final DateTime? proximoCorte;
  final DateTime? proximaFechaLimite;

  int get saldo => deuda.saldoActual;
  int? get limite => deuda.tarjetaLimiteCredito;
}

/// Análisis de deuda y crédito.
class AnalisisDeuda {
  const AnalisisDeuda({
    required this.rango,
    required this.deudas,
    required this.tarjetas,
    required this.movimientos,
    required this.saldoTotal,
    required this.saldoTarjetas,
    required this.saldoOtrasDeudas,
    required this.limiteTotal,
    required this.creditoDisponible,
    required this.hayTarjetas,
    required this.cargosDelPeriodo,
    required this.pagosDelPeriodo,
    required this.ajustesDelPeriodo,
  });

  final RangoPeriodo rango;

  /// Todas las deudas activas, tarjetas incluidas.
  final List<DeudaData> deudas;
  final List<TarjetaProyectada> tarjetas;

  /// Movimientos del periodo, más reciente primero.
  final List<MovimientoDeudaProyectado> movimientos;

  /// Saldos **a la fecha**, nunca del periodo.
  final int saldoTotal;
  final int saldoTarjetas;
  final int saldoOtrasDeudas;

  /// Suma de límites de las tarjetas que SÍ tienen límite capturado. No
  /// incluye préstamos ni financiamientos: una deuda que no es
  /// revolvente no tiene línea de crédito que reutilizar.
  final int limiteTotal;
  final int creditoDisponible;

  /// `false` cuando no existe ninguna TDC activa — distinto de "$0
  /// disponible".
  final bool hayTarjetas;

  /// Del periodo seleccionado.
  final int cargosDelPeriodo;
  final int pagosDelPeriodo;

  /// Ajustes y reversiones netos del periodo, con signo sobre el saldo.
  final int ajustesDelPeriodo;

  /// Fracción de la línea total en uso. `null` cuando no hay límite
  /// capturado en ninguna tarjeta.
  double? get utilizacionGlobal => limiteTotal == 0 ? null : saldoTarjetas / limiteTotal;
}

/// Análisis de deuda para Reportes.
///
/// No reimplementa el saldo: lo lee de `Deuda.saldoActual`, que el
/// dominio mantiene. Los agregados del periodo se derivan de
/// `MovimientoDeuda` con el MISMO criterio de dirección que usa el
/// repositorio, y el origen se resuelve por FK.
///
/// Sin N+1: una consulta de deudas y una de movimientos por deuda
/// existente (el universo de deudas de esta empresa es de decenas, no
/// de miles), resueltas antes del bucle de proyección.
class ObtenerAnalisisDeudaUseCase {
  ObtenerAnalisisDeudaUseCase(this._repository);

  final DeudaRepository _repository;

  Future<AnalisisDeuda> ejecutar({required RangoPeriodo rango, DateTime? hoy}) async {
    final referencia = hoy ?? DateTime.now();
    final diaHoy = DateTime(referencia.year, referencia.month, referencia.day);
    final desde = DateTime(rango.inicio.year, rango.inicio.month, rango.inicio.day);
    final hasta = DateTime(rango.fin.year, rango.fin.month, rango.fin.day, 23, 59, 59, 999);

    final deudas = await _repository.listar(estatus: EstatusDeuda.activa.name);

    final tarjetas = <TarjetaProyectada>[];
    var saldoTarjetas = 0;
    var saldoOtras = 0;
    var limiteTotal = 0;
    var creditoDisponible = 0;

    for (final deuda in deudas) {
      if (TipoDeuda.values.byName(deuda.tipo) != TipoDeuda.tarjetaCredito) {
        saldoOtras += deuda.saldoActual;
        continue;
      }
      saldoTarjetas += deuda.saldoActual;
      final disponible = creditoDisponibleTarjeta(
        limiteCredito: deuda.tarjetaLimiteCredito,
        saldoActual: deuda.saldoActual,
      );
      final limite = deuda.tarjetaLimiteCredito;
      if (limite != null && disponible != null) {
        limiteTotal += limite;
        creditoDisponible += disponible;
      }
      tarjetas.add(TarjetaProyectada(
        deuda: deuda,
        disponible: disponible,
        utilizacion: limite == null || limite == 0 ? null : deuda.saldoActual / limite,
        proximoCorte: deuda.tarjetaDiaCorte == null
            ? null
            : proximaOcurrenciaDiaDelMes(deuda.tarjetaDiaCorte!, diaHoy),
        proximaFechaLimite: proximaFechaPagoDeuda(deuda, diaHoy),
      ));
    }
    tarjetas.sort((a, b) => (b.utilizacion ?? -1).compareTo(a.utilizacion ?? -1));

    final movimientos = <MovimientoDeudaProyectado>[];
    var cargos = 0;
    var pagos = 0;
    var ajustes = 0;

    for (final deuda in deudas) {
      for (final m in await _repository.listarMovimientos(deuda.id)) {
        if (m.fecha.isBefore(desde) || m.fecha.isAfter(hasta)) continue;
        final tipo = TipoMovimientoDeuda.values.byName(m.tipo);
        final efecto = _efectoEnSaldo(tipo, m.importe);
        switch (tipo) {
          case TipoMovimientoDeuda.cargoCompra:
            cargos += m.importe;
          case TipoMovimientoDeuda.pago:
            pagos += m.importe;
          case TipoMovimientoDeuda.ajustePositivo:
          case TipoMovimientoDeuda.ajusteNegativo:
          case TipoMovimientoDeuda.reversionPago:
            ajustes += efecto;
          case TipoMovimientoDeuda.altaInicial:
          case TipoMovimientoDeuda.cancelacion:
            break;
        }
        movimientos.add(MovimientoDeudaProyectado(
          movimiento: m,
          deudaNombre: deuda.nombre,
          deudaId: deuda.id,
          tipo: tipo,
          origen: _origen(m, tipo),
          efectoEnSaldo: efecto,
        ));
      }
    }
    movimientos.sort((a, b) => b.fecha.compareTo(a.fecha));

    return AnalisisDeuda(
      rango: rango,
      deudas: deudas,
      tarjetas: tarjetas,
      movimientos: movimientos,
      saldoTotal: saldoTarjetas + saldoOtras,
      saldoTarjetas: saldoTarjetas,
      saldoOtrasDeudas: saldoOtras,
      limiteTotal: limiteTotal,
      creditoDisponible: creditoDisponible,
      hayTarjetas: tarjetas.isNotEmpty,
      cargosDelPeriodo: cargos,
      pagosDelPeriodo: pagos,
      ajustesDelPeriodo: ajustes,
    );
  }

  /// Mismo criterio de dirección que el repositorio: el importe siempre
  /// es positivo y el tipo decide el signo.
  static int _efectoEnSaldo(TipoMovimientoDeuda tipo, int importe) => switch (tipo) {
        TipoMovimientoDeuda.altaInicial => importe,
        TipoMovimientoDeuda.cargoCompra => importe,
        TipoMovimientoDeuda.ajustePositivo => importe,
        TipoMovimientoDeuda.reversionPago => importe,
        TipoMovimientoDeuda.pago => -importe,
        TipoMovimientoDeuda.ajusteNegativo => -importe,
        TipoMovimientoDeuda.cancelacion => -importe,
      };

  static OrigenMovimientoDeuda _origen(MovimientoDeudaData m, TipoMovimientoDeuda tipo) {
    if (m.compraId != null) return OrigenMovimientoDeuda.compra;
    if (m.tiempoExtraId != null) return OrigenMovimientoDeuda.tiempoExtra;
    if (m.costoAdicionalId != null) return OrigenMovimientoDeuda.costoAdicionalTiempoExtra;
    if (m.vehiculoMantenimientoId != null) return OrigenMovimientoDeuda.vehiculo;
    if (m.egresoGastoId != null) return OrigenMovimientoDeuda.egreso;
    // `egresoId` (sin `Gasto`) es el Egreso que MATERIALIZA un pago de
    // la tarjeta, no el gasto que la cargó — por eso se mira después y
    // sólo confirma que el movimiento es un pago.
    if (tipo == TipoMovimientoDeuda.pago || m.egresoId != null) return OrigenMovimientoDeuda.pago;
    if (tipo == TipoMovimientoDeuda.altaInicial) return OrigenMovimientoDeuda.apertura;
    return OrigenMovimientoDeuda.sinOrigen;
  }
}
