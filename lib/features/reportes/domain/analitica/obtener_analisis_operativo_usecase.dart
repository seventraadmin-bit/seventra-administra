import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/ingreso_repository.dart';

import '../usecases/clasificar_egresos_por_origen_usecase.dart';
import 'comparacion_periodo.dart';
import 'granularidad_serie.dart';

/// Un punto de la serie temporal — ingresos y gasto operativo de una
/// cubeta (día, semana o mes, según [GranularidadSerie]).
class PuntoOperativo {
  const PuntoOperativo({required this.cubeta, required this.ingresos, required this.gastoOperativo});

  final DateTime cubeta;
  final int ingresos;
  final int gastoOperativo;

  int get resultado => ingresos - gastoOperativo;
}

/// De qué se compone el gasto operativo del periodo.
///
/// La suma de todos los componentes es exactamente
/// [AnalisisOperativoPeriodo.gastoOperativo] — nunca "casi".
class ComponenteGasto {
  const ComponenteGasto({required this.origen, required this.importe});

  /// Reutiliza el vocabulario del clasificador único del proyecto. No
  /// se inventa una taxonomía paralela de categorías de gasto.
  final OrigenEgreso origen;
  final int importe;
}

/// Resultado operativo del periodo **y** su serie temporal **y** su
/// composición, calculados en una sola pasada.
///
/// Los totales no son consultas aparte: son el fold de las mismas filas
/// que alimentan [puntos] y [composicion]. Por eso es imposible que el
/// KPI diga $100,000 y la gráfica sume $97,000 — no hay dos caminos que
/// puedan desincronizarse, hay uno solo.
class AnalisisOperativoPeriodo {
  const AnalisisOperativoPeriodo({
    required this.rango,
    required this.granularidad,
    required this.puntos,
    required this.ingresos,
    required this.salidasDeEfectivo,
    required this.pagosDeDeuda,
    required this.cargosDeTarjeta,
    required this.composicion,
  });

  final RangoPeriodo rango;
  final GranularidadSerie granularidad;
  final List<PuntoOperativo> puntos;

  /// Ingresos `registrado` del periodo.
  final int ingresos;

  /// Salidas de efectivo reales (`Egreso` no financiado con TDC).
  final int salidasDeEfectivo;

  /// Porción de [salidasDeEfectivo] que fue a pagar una Deuda.
  final int pagosDeDeuda;

  /// Gasto reconocido por cargos a tarjeta, ya neteado de ajustes.
  final int cargosDeTarjeta;

  /// Ordenada de mayor a menor importe, sin componentes en cero.
  final List<ComponenteGasto> composicion;

  /// **La** definición de gasto operativo del sistema.
  ///
  /// Es la fórmula que Finanzas → Resumen ya usaba en
  /// `ResumenFinancieroState.egresosOperativos`, traída al dominio para
  /// que Reportes la consuma en vez de mantener una segunda aritmética.
  ///
  /// Pagar una tarjeta NO es gasto: el gasto se reconoció cuando se
  /// hizo el cargo ([cargosDeTarjeta]); contar también el pago sería
  /// doble conteo exacto del mismo peso. Y los cargos a tarjeta SÍ son
  /// gasto aunque todavía no muevan caja.
  int get gastoOperativo => salidasDeEfectivo - pagosDeDeuda + cargosDeTarjeta;

  int get resultadoOperativo => ingresos - gastoOperativo;

  /// Resultado como fracción de los ingresos (0.18 == 18 %).
  ///
  /// `null` cuando no hubo ingresos: un margen sobre cero no es cero ni
  /// −100 %, es indefinido, y la UI debe decirlo en vez de pintar una
  /// cifra falsa.
  double? get margenOperativo => ingresos == 0 ? null : resultadoOperativo / ingresos;
}

/// Fuente única de verdad de la capa analítica de Reportes.
///
/// Existe por un hallazgo real: `ResumenFinanciero.resultadoOperativo`
/// —lo que consumía Reportes → General— calculaba
/// `ingresos − egresos − comprasPorTdc`, mientras Finanzas → Resumen
/// calculaba `ingresos − (egresos − pagosDeDeuda + cargosDeTarjeta)`.
/// La primera contaba los pagos de tarjeta como gasto (doble conteo: el
/// cargo ya se había reconocido) y solo veía los cargos de Compras,
/// ignorando los de Tiempo Extra, mantenimiento vehicular y Egresos
/// manuales, sin netear cancelaciones. Las dos pantallas mostraban
/// números distintos para el mismo rango.
///
/// Aquí no se inventa una tercera regla: se conserva la de Finanzas —la
/// que pasó por las Etapas 19/19B/9— y ahora vive en el dominio, no en
/// un getter de estado de presentación.
///
/// Sin N+1: reutiliza `ClasificarEgresosPorOrigenUseCase` (que ya
/// resuelve todo en una pasada, sin consultas por fila) más dos
/// consultas acotadas por rango. Lo demás se calcula en memoria.
class ObtenerAnalisisOperativoUseCase {
  ObtenerAnalisisOperativoUseCase(this._ingresoRepository, this._deudaRepository, this._clasificarEgresos);

  final IngresoRepository _ingresoRepository;
  final DeudaRepository _deudaRepository;
  final ClasificarEgresosPorOrigenUseCase _clasificarEgresos;

  Future<AnalisisOperativoPeriodo> ejecutar({required RangoPeriodo rango, GranularidadSerie? granularidad}) async {
    // El extremo final se extiende al último instante del día: si el
    // llamador pasa la fecha a medianoche, un movimiento registrado esa
    // misma tarde quedaría fuera del reporte sin que nadie lo note.
    final desde = DateTime(rango.inicio.year, rango.inicio.month, rango.inicio.day);
    final hasta = DateTime(rango.fin.year, rango.fin.month, rango.fin.day, 23, 59, 59, 999);

    final ingresos = await _ingresoRepository.listar(estatus: 'registrado', rangoInicio: desde, rangoFin: hasta);
    final egresos = await _clasificarEgresos.ejecutar(rangoInicio: desde, rangoFin: hasta);
    final cargos = await _deudaRepository.listarCargosEnRango(rangoInicio: desde, rangoFin: hasta);

    final paso = granularidad ?? GranularidadSerie.paraRango(rango);
    final cubetas = paso.cubetas(rango);
    final ingresoPorCubeta = {for (final c in cubetas) c: 0};
    final gastoPorCubeta = {for (final c in cubetas) c: 0};
    final gastoPorOrigen = <OrigenEgreso, int>{};

    var totalIngresos = 0;
    for (final i in ingresos) {
      totalIngresos += i.monto;
      final cubeta = paso.cubetaDe(i.fecha);
      if (ingresoPorCubeta.containsKey(cubeta)) ingresoPorCubeta[cubeta] = ingresoPorCubeta[cubeta]! + i.monto;
    }

    void acumularGasto(DateTime fecha, OrigenEgreso origen, int importe) {
      gastoPorOrigen[origen] = (gastoPorOrigen[origen] ?? 0) + importe;
      final cubeta = paso.cubetaDe(fecha);
      if (gastoPorCubeta.containsKey(cubeta)) gastoPorCubeta[cubeta] = gastoPorCubeta[cubeta]! + importe;
    }

    var salidasDeEfectivo = 0;
    var pagosDeDeuda = 0;
    for (final ec in egresos.detalle) {
      salidasDeEfectivo += ec.egreso.monto;
      if (ec.origen == OrigenEgreso.deuda) {
        // Un pago de deuda no entra ni al KPI ni a la serie, por la
        // misma razón: el gasto ya se reconoció en la cubeta del cargo.
        pagosDeDeuda += ec.egreso.monto;
        continue;
      }
      acumularGasto(ec.egreso.fecha, ec.origen, ec.egreso.monto);
    }

    var cargosDeTarjeta = 0;
    for (final c in cargos) {
      cargosDeTarjeta += c.importeNeto;
      acumularGasto(c.fecha, _origenDeCargo(c), c.importeNeto);
    }

    final composicion = [
      for (final e in gastoPorOrigen.entries)
        if (e.value != 0) ComponenteGasto(origen: e.key, importe: e.value),
    ]..sort((a, b) => b.importe.compareTo(a.importe));

    return AnalisisOperativoPeriodo(
      rango: rango,
      granularidad: paso,
      puntos: [
        for (final c in cubetas)
          PuntoOperativo(cubeta: c, ingresos: ingresoPorCubeta[c]!, gastoOperativo: gastoPorCubeta[c]!),
      ],
      ingresos: totalIngresos,
      salidasDeEfectivo: salidasDeEfectivo,
      pagosDeDeuda: pagosDeDeuda,
      cargosDeTarjeta: cargosDeTarjeta,
      composicion: composicion,
    );
  }

  /// Origen de un cargo a tarjeta, resuelto SIEMPRE por FK — nunca por
  /// el texto del concepto. Un cargo sin ninguna FK de gasto es un
  /// Egreso manual financiado con TDC: cae en `manual`, que es
  /// exactamente lo que es.
  OrigenEgreso _origenDeCargo(CargoOperativoTarjeta c) {
    if (c.compraId != null) return OrigenEgreso.compra;
    if (c.tiempoExtraId != null || c.costoAdicionalId != null) return OrigenEgreso.tiempoExtra;
    if (c.vehiculoMantenimientoId != null) return OrigenEgreso.vehiculo;
    return OrigenEgreso.manual;
  }
}
