import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/area_repository.dart';

/// Solo activas — para el selector de Área al crear/editar un Puesto.
class ListarAreasActivasUseCase {
  ListarAreasActivasUseCase(this._repository);

  final AreaRepository _repository;

  Future<List<AreaData>> ejecutar() => _repository.listarActivas();
}
