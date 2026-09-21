import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/nomina/domain/repositories/nomina_repository.dart';

/// La próxima Nómina real pendiente de pago (Etapa 15, rediseño del
/// Dashboard) — Parte C.4 del pedido: "Debe tomar la próxima obligación
/// real de Nómina pendiente/cerrada... No mostrar una nómina ya pagada
/// como pendiente."
///
/// Reutiliza `NominaRepository.listarEnRango(estatus: 'cerrada')` (ya
/// existente) sin rango de fechas — trae TODAS las Nóminas `cerrada`
/// (nunca `pagada`, que por definición ya no es una obligación
/// pendiente — ver `PagoNominaRepositoryImpl._evaluarNominaPagada`) y
/// toma la de `fechaPagoOrdinaria` más próxima. `totalAPagar` se deriva
/// sumando los renglones reales, nunca un campo cacheado aparte.
class ObtenerProximaNominaUseCase {
  ObtenerProximaNominaUseCase(this._nominaRepository);

  final NominaRepository _nominaRepository;

  Future<NominaData?> ejecutar() async {
    final cerradas = await _nominaRepository.listarEnRango(estatus: 'cerrada');
    if (cerradas.isEmpty) return null;

    final ordenadas = [...cerradas]..sort((a, b) => a.fechaPagoOrdinaria.compareTo(b.fechaPagoOrdinaria));
    return ordenadas.first;
  }

  /// Total real a pagar de una Nómina — suma de `NominaEmpleado.totalAPagar`,
  /// nunca un campo cacheado en `Nomina`.
  Future<int> calcularTotal(String nominaId) async {
    final renglones = await _nominaRepository.listarEmpleados(nominaId);
    return renglones.fold<int>(0, (s, r) => s + r.totalAPagar);
  }
}
