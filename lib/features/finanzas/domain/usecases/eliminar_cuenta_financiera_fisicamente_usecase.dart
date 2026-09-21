import '../repositories/cuenta_financiera_repository.dart';

/// Eliminación física extraordinaria de una `CuentaFinanciera` (Etapa
/// 19C) — exclusiva del Usuario Maestro (`exigirMaestro`, nunca aquí;
/// este caso de uso es puro). Bloqueada si tiene cualquier
/// `Ingreso`/`Egreso` vinculado (pedido explícito: "una Cuenta
/// Financiera con movimientos históricos no debe eliminarse
/// físicamente de forma normal") — la validación completa vive en
/// `CuentaFinancieraRepositoryImpl.eliminarFisicamente`.
class EliminarCuentaFinancieraFisicamenteUseCase {
  EliminarCuentaFinancieraFisicamenteUseCase(this._repository);

  final CuentaFinancieraRepository _repository;

  Future<ResumenEliminacionCuentaFinanciera> obtenerResumen(String cuentaId) {
    return _repository.obtenerResumenEliminacionFisica(cuentaId);
  }

  Future<EliminarCuentaFinancieraFisicamenteResultado> ejecutar({
    required String cuentaId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    try {
      return await _repository.eliminarFisicamente(cuentaId: cuentaId, motivo: motivo, actorUsuarioId: actorUsuarioId);
    } catch (e) {
      return EliminarCuentaFinancieraFisicamenteErrorInesperado(e.toString());
    }
  }
}
