import 'package:riseg_one/features/reportes/domain/analitica/comparacion_periodo.dart';
import 'package:riseg_one/features/reportes/domain/analitica/granularidad_serie.dart';

import '../repositories/deuda_repository.dart';
import '../repositories/egreso_repository.dart';
import '../repositories/ingreso_repository.dart';

/// Un punto de la serie temporal — ingresos y gasto operativo de una
/// cubeta (día, semana o mes, según [GranularidadSerie]).
class PuntoOperativo {
  const PuntoOperativo({required this.cubeta, required this.ingresos, required this.gastoOperativo});

  final DateTime cubeta;
  final int ingresos;
  final int gastoOperativo;

  int get resultado => ingresos - gastoOperativo;
}

/// De qué se compone el gasto operativo del periodo, en las mismas
/// unidades y sumando exactamente [AnalisisOperativoPeriodo.gastoOperativo].
class ComponenteGasto {
  const ComponenteGasto({required this.clave, required this.importe});

  /// Clave estable (`nomina`, `compras`, `tiempoExtra`, ...). La
  /// etiqueta visible la resuelve la UI con `AppLocalizations` — este
  /// objeto nunca carga texto localizado.
  final String clave;
  final int importe;
}

/// Resultado operativo del periodo **y** su serie temporal, calculados
/// en una sola pasada.
///
/// Los totales NO son consultas aparte: son el fold de las mismas filas
/// que alimentan [puntos] y [composicion]. Por eso es imposible que el
/// KPI diga $100,000 y la gráfica sume $97,000 — no hay dos caminos que
/// puedan desincronizarse, hay uno solo (§16).
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

  final List<ComponenteGasto> composicion;

  /// **La** definición de gasto operativo del sistema.
  ///
  /// Es literalmente la fórmula que Finanzas → Resumen ya usaba en
  /// `ResumenFinancieroState.egresosOperativos`, movida aquí para que
  /// Reportes la consuma en vez de mantener una segunda aritmética.
  ///
  /// Pagar una tarjeta NO es gasto: el gasto se reconoció cuando se
  /// hizo el cargo ([cargosDeTarjeta]); contar también el pago sería
  /// doble conteo exacto del mismo peso. Y los cargos a tarjeta SÍ son
  /// gasto aunque no muevan caja todavía.
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
/// (que consumía Reportes → General) calculaba
/// `ingresos - egresos - comprasPorTdc`, mientras Finanzas → Resumen
/// calculaba `ingresos - (egresos - pagosDeDeuda + cargosDeTarjeta)`.
/// La primera contaba los pagos de tarjeta como gasto —doble conteo,
/// porque el cargo ya se había reconocido— y solo veía los cargos de
/// Compras, ignorando los de Tiempo Extra, mantenimiento vehicular y
/// Egresos manuales, y sin netear cancelaciones. Las dos pantallas
/// mostraban números distintos para el mismo rango.
///
/// Aquí no se inventa una tercera regla: se conserva la de Finanzas,
/// que es la que pasó por las Etapas 19/19B/9, y ahora vive en el
/// dominio en vez de en un getter de estado de presentación.
///
/// Sin N+1: cuatro consultas acotadas por rango, todo lo demás se
/// resuelve en memoria.
class ObtenerAnalisisOperativoUseCase {
  ObtenerAnalisisOperativoUseCase(this._ingresoRepository, this._egresoRepository, this._deudaRepository);

  final IngresoRepository _ingresoRepository;
  final EgresoRepository _egresoRepository;
  final DeudaRepository _deudaRepository;

  Future<AnalisisOperativoPeriodo> ejecutar({required RangoPeriodo rango, GranularidadSerie? granularidad}) async {
    // El extremo final se extiende al último instante del día: si el
    // llamador pasa la fecha a medianoche, un movimiento registrado esa
    // misma tarde quedaría fuera del reporte sin que nadie lo note.
    final hasta = DateTime(rango.fin.year, rango.fin.month, rango.fin.day, 23, 59, 59, 999);
    final desde = DateTime(rango.inicio.year, rango.inicio.month, rango.inicio.day);

    final ingresos = await _ingresoRepository.listar(estatus: 'registrado', rangoInicio: desde, rangoFin: hasta);
    final egresos = await _egresoRepository.listar(
      estatus: 'registrado',
      rangoInicio: desde,
      rangoFin: hasta,
      soloSalidaDeEfectivo: true,
    );
    final egresoIdsDePagosDeDeuda =
        (await _deudaRepository.listarEgresoIdsDePagosEnRango(rangoInicio: desde, rangoFin: hasta)).toSet();
    final cargos = await _deudaRepository.listarCargosEnRango(rangoInicio: desde, rangoFin: hasta);

    final paso = granularidad ?? GranularidadSerie.paraRango(rango);
    final cubetas = paso.cubetas(rango);
    final ingresoPorCubeta = {for (final c in cubetas) c: 0};
    final gastoPorCubeta = {for (final c in cubetas) c: 0};

    var totalIngresos = 0;
    for (final i in ingresos) {
      totalIngresos += i.monto;
      final cubeta = paso.cubetaDe(i.fecha);
      if (ingresoPorCubeta.containsKey(cubeta)) ingresoPorCubeta[cubeta] = ingresoPorCubeta[cubeta]! + i.monto;
    }

    var salidasDeEfectivo = 0;
    var pagosDeDeuda = 0;
    for (final e in egresos) {
      salidasDeEfectivo += e.monto;
      final esPagoDeDeuda = egresoIdsDePagosDeDeuda.contains(e.id);
      if (esPagoDeDeuda) {
        pagosDeDeuda += e.monto;
        // Un pago de deuda no entra a la serie de gasto por la misma
        // razón por la que no entra al KPI: el gasto ya se reconoció
        // en la cubeta del cargo.
        continue;
      }
      final cubeta = paso.cubetaDe(e.fecha);
      if (gastoPorCubeta.containsKey(cubeta)) gastoPorCubeta[cubeta] = gastoPorCubeta[cubeta]! + e.monto;
    }

    var cargosDeTarjeta = 0;
    for (final c in cargos) {
      cargosDeTarjeta += c.importeNeto;
      final cubeta = paso.cubetaDe(c.fecha);
      if (gastoPorCubeta.containsKey(cubeta)) gastoPorCubeta[cubeta] = gastoPorCubeta[cubeta]! + c.importeNeto;
    }

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
      composicion: const [],
    );
  }
}
