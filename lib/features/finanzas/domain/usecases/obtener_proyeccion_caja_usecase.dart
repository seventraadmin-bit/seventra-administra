import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_por_cobrar_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/calcular_fecha_tarjeta_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';
import 'package:riseg_one/features/nomina/domain/repositories/nomina_repository.dart';
import 'package:riseg_one/features/nomina/domain/repositories/pago_nomina_repository.dart';
import 'resolver_nombres_contraparte_usecase.dart';

import '../repositories/cuenta_financiera_repository.dart';
import 'package:riseg_one/features/finanzas/domain/contraparte_cobro.dart';

enum TipoCompromiso { entrada, salida }

enum OrigenCompromiso { cuentaPorCobrar, nomina, deuda }

/// Un compromiso financiero real, respaldado por un dato ya persistido
/// — nunca un promedio ni una estimación inventada. Ver el doc comment
/// de `ObtenerProyeccionCajaUseCase` para las fuentes admitidas.
/// Nunca representa una obligación ya vencida sin fecha nueva conocida
/// (ver `ProyeccionCaja.pendientesVencidos` para esas).
class CompromisoFinanciero {
  const CompromisoFinanciero({
    required this.fecha,
    required this.concepto,
    required this.tipo,
    required this.origen,
    required this.importe,
    required this.origenId,
    this.vencida = false,
  });

  final DateTime fecha;
  final String concepto;
  final TipoCompromiso tipo;
  final OrigenCompromiso origen;
  final int importe;

  /// Id de la `CuentaPorCobrar`/`Nomina`/`Deuda` de origen — para
  /// navegar (siempre mediante FK/relaciones reales, nunca texto).
  final String origenId;

  /// `true` únicamente cuando este compromiso es una CxC que estaba
  /// vencida y volvió a la proyección por tener
  /// `fechaCobroReprogramada` (Etapa 19D) — nunca aparece en `true`
  /// para un compromiso que nunca estuvo vencido.
  final bool vencida;
}

enum TipoPendienteVencido { cobro, pago }

/// Una obligación real cuya fecha conocida ya pasó y sigue pendiente
/// (Etapa 19D, "Calendario financiero y planeación de liquidez") — se
/// muestra por separado, nunca se asigna arbitrariamente a una fecha
/// futura en la proyección (su fecha real de cobro/pago ya no es
/// predecible). Una CxC sale de este bloque únicamente cuando se le
/// captura `fechaCobroReprogramada` (vuelve a `compromisos` en esa
/// fecha nueva). Nómina/Deuda no tienen mecanismo de reprogramación en
/// esta etapa — permanecen aquí hasta que se paguen o se corrijan por
/// su propio flujo ya existente.
class PendienteVencido {
  const PendienteVencido({
    required this.concepto,
    required this.tipo,
    required this.origen,
    required this.importe,
    required this.origenId,
    required this.fechaVencimiento,
    required this.diasVencido,
  });

  final String concepto;
  final TipoPendienteVencido tipo;
  final OrigenCompromiso origen;
  final int importe;
  final String origenId;
  final DateTime fechaVencimiento;
  final int diasVencido;
}

class ProyeccionCaja {
  const ProyeccionCaja({
    required this.cuentasConfiguradas,
    required this.saldoActual,
    required this.compromisos,
    required this.pendientesVencidos,
  });

  /// `false` si no hay ninguna `CuentaFinanciera` activa — en ese caso
  /// `saldoActual`/`saldoProyectado` son `0` pero NO deben mostrarse
  /// como un dato real (nunca fingir disponibilidad).
  final bool cuentasConfiguradas;
  final int saldoActual;
  final List<CompromisoFinanciero> compromisos;

  /// Cobros/pagos vencidos (ver `PendienteVencido`) — siempre "a hoy",
  /// independiente del rango `desde`/`hasta` pedido (Etapa 19D: es un
  /// bloque fijo, no se acota por mes visible).
  final List<PendienteVencido> pendientesVencidos;

  int get entradasPrevistas =>
      compromisos.where((c) => c.tipo == TipoCompromiso.entrada).fold<int>(0, (s, c) => s + c.importe);

  int get salidasComprometidas =>
      compromisos.where((c) => c.tipo == TipoCompromiso.salida).fold<int>(0, (s, c) => s + c.importe);

  int get saldoProyectado => saldoActual + entradasPrevistas - salidasComprometidas;
}

DateTime _sinHora(DateTime fecha) => DateTime(fecha.year, fecha.month, fecha.day);

/// Proyección de caja (Etapas 19C/19D) — `saldoActual` (posición de
/// caja de hoy) + compromisos reales con fecha efectiva dentro de
/// `[desde, hasta]`. Único punto de verdad: tanto el Resumen financiero
/// (`desde == hoy`) como la Planeación financiera (`desde`/`hasta` del
/// mes visible) consumen esta misma implementación — nunca una segunda
/// lógica de proyección.
///
/// Únicas 3 fuentes de "salidas comprometidas"/"entradas previstas"
/// admitidas (nunca compras futuras, gastos promedio, ni estimaciones
/// de `DocumentoPorEmitir`):
///
/// 1. **Entradas** — `CuentaPorCobrar` con `estatus != pagada` y
///    `fechaVencimiento` real, sumando `saldoPendiente` (nunca
///    `importeEmitido` — un cobro parcial ya está reflejado en el
///    saldo). Una CxC **vencida** (fecha < hoy) solo entra a
///    `compromisos` si tiene `fechaCobroReprogramada` (con `vencida:
///    true`, en esa fecha nueva); sin reprogramar, va a
///    `pendientesVencidos` — Etapa 19D, corrección de raíz: la fecha
///    real de cobro de una obligación vencida ya no es conocida, así
///    que nunca se le asigna una fecha futura inventada.
/// 2. **Salidas — Nómina** — `Nomina.estatus == cerrada` (nunca
///    `pagada`, que ya no es una obligación pendiente; nunca
///    `borrador`, que no es un compromiso real todavía), monto =
///    `SUM(NominaEmpleado.totalAPagar) − SUM(aplicado)` (Etapa 19D,
///    corrección de raíz: un pago parcial de Nómina ya reduce lo
///    realmente pendiente, vía `PagoNominaRepository
///    .totalAplicadoPorRenglon`, batch — nunca N+1). Si
///    `fechaPagoOrdinaria` ya pasó y el saldo sigue > 0, es un "pago
///    vencido" (`pendientesVencidos`), nunca un compromiso futuro.
/// 3. **Salidas — Deuda** — solo si `pagoProgramado != null` (un monto
///    real comprometido), importe = `min(pagoProgramado, saldoActual)`
///    (Etapa 19D, corrección de raíz: nunca proyectar más de lo que
///    realmente se debe) y `saldoActual > 0` (una tarjeta en $0 no
///    genera compromiso). Para tarjeta: fecha =
///    `proximaOcurrenciaDiaDelMes(tarjetaDiaPago, hoy)` — por
///    construcción siempre `>= hoy`, nunca puede estar vencida. Para
///    préstamo/financiamiento: fecha = `fechaVencimiento`; si ya pasó y
///    el saldo sigue > 0, es un "pago vencido".
class ObtenerProyeccionCajaUseCase {
  ObtenerProyeccionCajaUseCase(
    this._cuentaFinancieraRepository,
    this._cuentaPorCobrarRepository,
    this._resolverNombres,
    this._nominaRepository,
    this._pagoNominaRepository,
    this._deudaRepository,
  );

  final CuentaFinancieraRepository _cuentaFinancieraRepository;
  final CuentaPorCobrarRepository _cuentaPorCobrarRepository;
  final ResolverNombresContraparteUseCase _resolverNombres;
  final NominaRepository _nominaRepository;
  final PagoNominaRepository _pagoNominaRepository;
  final DeudaRepository _deudaRepository;

  Future<ProyeccionCaja> ejecutar({required DateTime hoy, DateTime? desde, required DateTime hasta}) async {
    // Fecha-solo: un compromiso con fecha efectiva "hoy" (sin hora) debe
    // incluirse durante todo el día, no solo antes de la hora actual de
    // `hoy` — comparar contra `hoy` con su hora real excluía de raíz
    // cualquier CxC/Nómina/Deuda con fecha exactamente hoy la mayor
    // parte del día.
    final rangoDesde = _sinHora(desde ?? hoy);
    final cuentasActivas = await _cuentaFinancieraRepository.listar(soloActivas: true);
    final cuentasConfiguradas = cuentasActivas.isNotEmpty;
    var saldoActual = 0;
    if (cuentasConfiguradas) {
      final saldos = await _cuentaFinancieraRepository.calcularSaldos(cuentasActivas.map((c) => c.id));
      saldoActual = saldos.values.fold<int>(0, (s, v) => s + v);
    }

    final compromisos = <CompromisoFinanciero>[];
    final pendientesVencidos = <PendienteVencido>[];
    final hoySinHora = _sinHora(hoy);

    // 1. Cuentas por cobrar — entradas previstas / cobros vencidos.
    final cuentasPorCobrar = await _cuentaPorCobrarRepository.listar();
    // schemaVersion 88 — la contraparte puede ser un eventual, así que
    // el nombre se resuelve por el único camino que conoce los dos
    // tipos. Antes un cobro eventual entraba a la proyección sin
    // concepto.
    final nombres = await _resolverNombres.paraCuentas(cuentasPorCobrar);
    for (final cxc in cuentasPorCobrar) {
      if (EstatusCuentaPorCobrar.values.byName(cxc.estatus) == EstatusCuentaPorCobrar.pagada) continue;
      final vencimiento = cxc.fechaVencimiento;
      if (vencimiento == null) continue;
      final concepto = nombres.de(contraparteDeCuenta(cxc));
      final vencida = estaVencida(cxc, hoy);

      if (vencida) {
        final reprogramada = cxc.fechaCobroReprogramada;
        if (reprogramada == null) {
          pendientesVencidos.add(PendienteVencido(
            concepto: concepto,
            tipo: TipoPendienteVencido.cobro,
            origen: OrigenCompromiso.cuentaPorCobrar,
            importe: cxc.saldoPendiente,
            origenId: cxc.id,
            fechaVencimiento: vencimiento,
            diasVencido: hoySinHora.difference(_sinHora(vencimiento)).inDays,
          ));
          continue;
        }
        if (reprogramada.isBefore(rangoDesde) || reprogramada.isAfter(hasta)) continue;
        compromisos.add(CompromisoFinanciero(
          fecha: reprogramada,
          concepto: concepto,
          tipo: TipoCompromiso.entrada,
          origen: OrigenCompromiso.cuentaPorCobrar,
          importe: cxc.saldoPendiente,
          origenId: cxc.id,
          vencida: true,
        ));
        continue;
      }

      if (vencimiento.isBefore(rangoDesde) || vencimiento.isAfter(hasta)) continue;
      compromisos.add(CompromisoFinanciero(
        fecha: vencimiento,
        concepto: concepto,
        tipo: TipoCompromiso.entrada,
        origen: OrigenCompromiso.cuentaPorCobrar,
        importe: cxc.saldoPendiente,
        origenId: cxc.id,
      ));
    }

    // 2. Salidas comprometidas — Nómina cerrada pendiente de pago
    // (nunca `pagada`, mismo criterio que `ObtenerProximaNominaUseCase`),
    // descontando lo ya aplicado en pagos parciales. Renglones de TODAS
    // las Nóminas cerradas en una sola consulta (`listarRenglonesEnRango`,
    // el mismo método batch que ya usa Reportes) — la versión anterior
    // hacía un `listarEmpleados(nomina.id)` por Nómina, un N+1 real
    // (auditoría integral 19A-19D).
    final nominasCerradas = await _nominaRepository.listarEnRango(estatus: 'cerrada');
    final renglones = await _nominaRepository.listarRenglonesEnRango(estatus: 'cerrada');
    final renglonesPorNomina = <String, List<String>>{};
    final renglonesTodos = <String, int>{};
    for (final r in renglones) {
      renglonesPorNomina.putIfAbsent(r.nominaId, () => []).add(r.id);
      renglonesTodos[r.id] = r.totalAPagar;
    }
    final aplicadoPorRenglon = await _pagoNominaRepository.totalAplicadoPorRenglon(renglonesTodos.keys.toList());
    for (final nomina in nominasCerradas) {
      final ids = renglonesPorNomina[nomina.id] ?? const [];
      final total = ids.fold<int>(0, (s, id) => s + (renglonesTodos[id] ?? 0));
      final aplicado = ids.fold<int>(0, (s, id) => s + (aplicadoPorRenglon[id] ?? 0));
      final pendiente = total - aplicado;
      if (pendiente <= 0) continue;

      final fechaPagoSinHora = _sinHora(nomina.fechaPagoOrdinaria);
      if (fechaPagoSinHora.isBefore(hoySinHora)) {
        pendientesVencidos.add(PendienteVencido(
          concepto: 'Nómina ${nomina.folio}',
          tipo: TipoPendienteVencido.pago,
          origen: OrigenCompromiso.nomina,
          importe: pendiente,
          origenId: nomina.id,
          fechaVencimiento: nomina.fechaPagoOrdinaria,
          diasVencido: hoySinHora.difference(fechaPagoSinHora).inDays,
        ));
        continue;
      }
      if (nomina.fechaPagoOrdinaria.isBefore(rangoDesde) || nomina.fechaPagoOrdinaria.isAfter(hasta)) continue;
      compromisos.add(CompromisoFinanciero(
        fecha: nomina.fechaPagoOrdinaria,
        concepto: 'Nómina ${nomina.folio}',
        tipo: TipoCompromiso.salida,
        origen: OrigenCompromiso.nomina,
        importe: pendiente,
        origenId: nomina.id,
      ));
    }

    // 3. Salidas comprometidas — Deuda con pago programado real.
    final deudasActivas = await _deudaRepository.listar(estatus: 'activa');
    for (final deuda in deudasActivas) {
      final pagoProgramado = deuda.pagoProgramado;
      if (pagoProgramado == null || pagoProgramado <= 0) continue;
      if (deuda.saldoActual <= 0) continue;
      final importe = pagoProgramado < deuda.saldoActual ? pagoProgramado : deuda.saldoActual;

      final esTarjeta = deuda.tipo == TipoDeuda.tarjetaCredito.name;
      final DateTime? fecha = esTarjeta
          ? (deuda.tarjetaDiaPago == null ? null : proximaOcurrenciaDiaDelMes(deuda.tarjetaDiaPago!, hoy))
          : deuda.fechaVencimiento;
      if (fecha == null) continue;

      // Tarjeta nunca puede estar vencida: `proximaOcurrenciaDiaDelMes`
      // siempre deriva una fecha >= hoy por construcción.
      if (!esTarjeta && _sinHora(fecha).isBefore(hoySinHora)) {
        pendientesVencidos.add(PendienteVencido(
          concepto: deuda.nombre,
          tipo: TipoPendienteVencido.pago,
          origen: OrigenCompromiso.deuda,
          importe: importe,
          origenId: deuda.id,
          fechaVencimiento: fecha,
          diasVencido: hoySinHora.difference(_sinHora(fecha)).inDays,
        ));
        continue;
      }
      if (fecha.isBefore(rangoDesde) || fecha.isAfter(hasta)) continue;

      compromisos.add(CompromisoFinanciero(
        fecha: fecha,
        concepto: deuda.nombre,
        tipo: TipoCompromiso.salida,
        origen: OrigenCompromiso.deuda,
        importe: importe,
        origenId: deuda.id,
      ));
    }

    compromisos.sort((a, b) => a.fecha.compareTo(b.fecha));
    pendientesVencidos.sort((a, b) => b.diasVencido.compareTo(a.diasVencido));

    return ProyeccionCaja(
      cuentasConfiguradas: cuentasConfiguradas,
      saldoActual: saldoActual,
      compromisos: compromisos,
      pendientesVencidos: pendientesVencidos,
    );
  }
}
