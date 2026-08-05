import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/puesto_repository.dart';

/// Wrapper delgado sobre `PuestoRepository.listarActivos()` — la UI
/// nunca consulta el repositorio directamente, mismo motivo que
/// `ListarSucursalesUseCase`.
class ListarPuestosUseCase {
  ListarPuestosUseCase(this._repository);

  final PuestoRepository _repository;

  Future<List<PuestoData>> ejecutar() => _repository.listarActivos();
}
