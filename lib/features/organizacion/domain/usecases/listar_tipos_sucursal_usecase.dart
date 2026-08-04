import '../repositories/catalogo_repository.dart';

/// Único punto por el que la pantalla de Sucursal obtiene el catálogo de
/// Tipo de Sucursal — la UI nunca consulta Drift/el repositorio
/// directamente, ni siquiera para un catálogo de solo lectura.
class ListarTiposSucursalUseCase {
  ListarTiposSucursalUseCase(this._repository);

  final CatalogoRepository _repository;

  Future<List<CatalogoItem>> ejecutar() => _repository.listarTiposSucursal();
}
