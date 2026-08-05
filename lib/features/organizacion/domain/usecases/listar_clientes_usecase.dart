import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/cliente_repository.dart';

/// Wrapper delgado sobre `ClienteRepository.listarActivos()` — la UI
/// nunca consulta el repositorio directamente, mismo motivo que
/// `ListarPuestosUseCase`.
class ListarClientesUseCase {
  ListarClientesUseCase(this._repository);

  final ClienteRepository _repository;

  Future<List<ClienteData>> ejecutar() => _repository.listarActivos();
}
