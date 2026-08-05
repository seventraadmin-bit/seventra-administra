import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/area_repository.dart';

/// Todas las Áreas (activas e inactivas) — para el listado propio de
/// Áreas.
class ListarAreasUseCase {
  ListarAreasUseCase(this._repository);

  final AreaRepository _repository;

  Future<List<AreaData>> ejecutar() => _repository.listarTodas();
}
