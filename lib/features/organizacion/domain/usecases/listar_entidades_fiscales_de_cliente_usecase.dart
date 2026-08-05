import '../repositories/entidad_fiscal_repository.dart';

/// Wrapper delgado sobre `EntidadFiscalRepository.listarPorCliente()` —
/// la UI nunca consulta el repositorio directamente, mismo motivo que
/// `ListarPuestosUseCase`. Incluye activas y archivadas — una archivada
/// debe seguir siendo encontrable para reactivarla.
class ListarEntidadesFiscalesDeClienteUseCase {
  ListarEntidadesFiscalesDeClienteUseCase(this._repository);

  final EntidadFiscalRepository _repository;

  Future<List<EntidadFiscalConDomicilio>> ejecutar(String clienteId) => _repository.listarPorCliente(clienteId);
}
