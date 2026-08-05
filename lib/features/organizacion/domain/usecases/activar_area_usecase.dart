import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/area_repository.dart';

/// Reactivar un Área nunca está bloqueado — la única transición
/// restringida es Desactivar (ver `DesactivarAreaUseCase`).
class ActivarAreaUseCase {
  ActivarAreaUseCase(this._repository);

  final AreaRepository _repository;

  Future<AreaData> ejecutar(String areaId) => _repository.activar(areaId);
}
