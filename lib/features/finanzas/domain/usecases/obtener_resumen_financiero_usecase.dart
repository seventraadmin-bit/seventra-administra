import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import '../repositories/egreso_repository.dart';
import '../repositories/ingreso_repository.dart';

/// Resumen financiero base (Etapa 4K.1) — Resolución 5 de Marlon:
/// consultas de Total de Ingresos, Total de Egresos y Resultado
/// operativo, aunque todavía no exista una pantalla de reportes
/// dedicada.
///
/// [totalEgresos] es deliberadamente el total CRUDO de `Egreso` reales
/// (flujo de caja) — otros consumidores (`ResumenFinancieroController.
/// egresosPeriodo`/`flujoDespuesDeuda`) dependen de que sea
/// exactamente eso, nunca un estimado. [totalComprasPorTdc] (Etapa 3)
/// es la porción de gasto reconocido que una Compra pagada con TDC
/// genera SIN crear ningún `Egreso` — [resultadoOperativo] la incluye
/// para que cambiar el origen financiero de una Compra (Cuenta↔TDC)
/// nunca altere el gasto operativo reconocido, mientras [totalEgresos]
/// se mantiene fiel a su significado original de "salidas de caja
/// reales".
class ResumenFinanciero {
  const ResumenFinanciero({required this.totalIngresos, required this.totalEgresos, this.totalComprasPorTdc = 0});

  final int totalIngresos;
  final int totalEgresos;
  final int totalComprasPorTdc;

  int get resultadoOperativo => totalIngresos - totalEgresos - totalComprasPorTdc;
}

class ObtenerResumenFinancieroUseCase {
  ObtenerResumenFinancieroUseCase(this._ingresoRepository, this._egresoRepository, this._compraRepository);

  final IngresoRepository _ingresoRepository;
  final EgresoRepository _egresoRepository;
  final CompraRepository _compraRepository;

  Future<ResumenFinanciero> ejecutar({DateTime? rangoInicio, DateTime? rangoFin}) async {
    final totalIngresos = await _ingresoRepository.totalIngresos(rangoInicio: rangoInicio, rangoFin: rangoFin);
    final totalEgresos = await _egresoRepository.totalEgresos(rangoInicio: rangoInicio, rangoFin: rangoFin);
    final totalComprasPorTdc =
        await _compraRepository.totalCompradoPorTdcEnRango(rangoInicio: rangoInicio, rangoFin: rangoFin);
    return ResumenFinanciero(totalIngresos: totalIngresos, totalEgresos: totalEgresos, totalComprasPorTdc: totalComprasPorTdc);
  }
}
