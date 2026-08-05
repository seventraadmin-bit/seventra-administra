import '../repositories/servicio_repository.dart';

/// Wrapper delgado sobre `ServicioRepository.listar()` — la UI nunca
/// consulta el repositorio directamente, mismo motivo que
/// `ListarPuestosUseCase`/`ListarEntidadesFiscalesDeClienteUseCase`. El
/// filtrado por texto de búsqueda vive en el estado de la pantalla (en
/// memoria), no aquí — mismo patrón que `ClientesListState`.
class ListarServiciosUseCase {
  ListarServiciosUseCase(this._repository);

  final ServicioRepository _repository;

  Future<List<ServicioListItem>> ejecutar() => _repository.listar();
}
