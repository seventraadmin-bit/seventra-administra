import '../repositories/egreso_repository.dart';
import '../repositories/ingreso_repository.dart';

class FlujoEfectivo {
  const FlujoEfectivo({required this.entradas, required this.salidas});

  final int entradas;
  final int salidas;

  int get flujoNeto => entradas - salidas;
}

/// Flujo de efectivo del periodo (Etapa 19C, Parte D) — deliberadamente
/// distinto de `resultadoOperativo`: `Egreso` YA incluye todo egreso
/// real, incluidos los pagos de deuda (que nunca vuelven a ser gasto
/// operativo, pero sí son salida de caja), así que `totalEgresos`
/// *es* "salidas de efectivo" sin ningún ajuste adicional. No se
/// recalcula nada — solo se re-etiqueta junto a `resultadoOperativo`
/// para que la separación conceptual sea visual, no solo numérica.
class ObtenerFlujoEfectivoUseCase {
  ObtenerFlujoEfectivoUseCase(this._ingresoRepository, this._egresoRepository);

  final IngresoRepository _ingresoRepository;
  final EgresoRepository _egresoRepository;

  Future<FlujoEfectivo> ejecutar({DateTime? rangoInicio, DateTime? rangoFin}) async {
    final entradas = await _ingresoRepository.totalIngresos(rangoInicio: rangoInicio, rangoFin: rangoFin);
    final salidas = await _egresoRepository.totalEgresos(rangoInicio: rangoInicio, rangoFin: rangoFin);
    return FlujoEfectivo(entradas: entradas, salidas: salidas);
  }
}
