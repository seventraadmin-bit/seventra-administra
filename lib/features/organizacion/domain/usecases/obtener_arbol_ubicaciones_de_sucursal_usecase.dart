import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';

import '../repositories/ubicacion_repository.dart';

/// Compone "resolver la raíz de esta Sucursal" + "ensamblar su árbol" —
/// la pantalla de expediente de Sucursal solo conoce el `sucursalId`,
/// nunca el id de la Ubicación raíz.
class ObtenerArbolUbicacionesDeSucursalUseCase {
  ObtenerArbolUbicacionesDeSucursalUseCase(this._repository);

  final UbicacionRepository _repository;

  Future<Result<UbicacionArbol>> ejecutar(String sucursalId) async {
    final raiz = await _repository.obtenerRaizDeSucursal(sucursalId);
    if (raiz == null) {
      return Result.failure(NotFoundFailure('La Sucursal $sucursalId no tiene una Ubicación raíz.'));
    }
    return Result.ok(await _repository.obtenerArbol(raiz.id));
  }
}
