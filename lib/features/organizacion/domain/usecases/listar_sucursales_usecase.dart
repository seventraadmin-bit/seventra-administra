import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/sucursal_repository.dart';

/// Wrapper delgado sobre `SucursalRepository.listarActivas()` — existe
/// para que la pantalla de listado dependa de un caso de uso, nunca
/// directamente del repositorio (mismo motivo que `ListarTiposSucursalUseCase`).
class ListarSucursalesUseCase {
  ListarSucursalesUseCase(this._repository);

  final SucursalRepository _repository;

  Future<List<SucursalData>> ejecutar() => _repository.listarActivas();
}
