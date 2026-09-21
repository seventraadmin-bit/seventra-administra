import '../repositories/deuda_repository.dart';

/// Eliminación física extraordinaria de una `Deuda` (Etapa 19) —
/// exclusiva del Usuario Maestro (`exigirMaestro`, nunca aquí; este
/// caso de uso es puro). Toda la validación de dependencias + snapshot
/// + registro de auditoría + `DELETE` (Deuda, sus `MovimientoDeuda`, y
/// los `Egreso` que generó) ocurre transaccionalmente dentro de
/// `DeudaRepositoryImpl.eliminarFisicamente`.
class EliminarDeudaFisicamenteUseCase {
  EliminarDeudaFisicamenteUseCase(this._repository);

  final DeudaRepository _repository;

  Future<ResumenEliminacionDeuda> obtenerResumen(String deudaId) {
    return _repository.obtenerResumenEliminacionFisica(deudaId);
  }

  Future<EliminarDeudaFisicamenteResultado> ejecutar({
    required String deudaId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    try {
      return await _repository.eliminarFisicamente(
        deudaId: deudaId,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarDeudaFisicamenteErrorInesperado(e.toString());
    }
  }
}
