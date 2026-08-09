import '../repositories/egreso_repository.dart';
import '../repositories/ingreso_repository.dart';

/// Resumen financiero base (Etapa 4K.1) — Resolución 5 de Marlon:
/// consultas de Total de Ingresos, Total de Egresos y Resultado
/// operativo, aunque todavía no exista una pantalla de reportes
/// dedicada.
class ResumenFinanciero {
  const ResumenFinanciero({required this.totalIngresos, required this.totalEgresos});

  final int totalIngresos;
  final int totalEgresos;

  int get resultadoOperativo => totalIngresos - totalEgresos;
}

class ObtenerResumenFinancieroUseCase {
  ObtenerResumenFinancieroUseCase(this._ingresoRepository, this._egresoRepository);

  final IngresoRepository _ingresoRepository;
  final EgresoRepository _egresoRepository;

  Future<ResumenFinanciero> ejecutar({DateTime? rangoInicio, DateTime? rangoFin}) async {
    final totalIngresos = await _ingresoRepository.totalIngresos(rangoInicio: rangoInicio, rangoFin: rangoFin);
    final totalEgresos = await _egresoRepository.totalEgresos(rangoInicio: rangoInicio, rangoFin: rangoFin);
    return ResumenFinanciero(totalIngresos: totalIngresos, totalEgresos: totalEgresos);
  }
}
