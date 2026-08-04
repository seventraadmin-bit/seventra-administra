import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';

import '../repositories/ubicacion_repository.dart';

/// Ensambla el árbol completo a partir de una raíz — lógica real
/// (recorrido recursivo), reutilizable por el futuro selector visual de
/// ubicaciones.
class ObtenerArbolUbicacionesUseCase {
  ObtenerArbolUbicacionesUseCase(this._repository);

  final UbicacionRepository _repository;

  Future<Result<UbicacionArbol>> ejecutar(String raizId) async {
    try {
      return Result.ok(await _repository.obtenerArbol(raizId));
    } on StateError catch (e) {
      return Result.failure(NotFoundFailure(e.message));
    }
  }
}
