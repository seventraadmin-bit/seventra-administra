import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';

import '../repositories/empresa_repository.dart';

/// Única forma bendecida de obtener "la" Empresa — evita que cada
/// llamador futuro repita mal el invariante de singleton.
class ObtenerEmpresaActivaUseCase {
  ObtenerEmpresaActivaUseCase(this._repository);

  final EmpresaRepository _repository;

  Future<Result<EmpresaData>> ejecutar() async {
    try {
      return Result.ok(await _repository.obtenerActiva());
    } on StateError catch (e) {
      return Result.failure(NotFoundFailure(e.message));
    }
  }
}
