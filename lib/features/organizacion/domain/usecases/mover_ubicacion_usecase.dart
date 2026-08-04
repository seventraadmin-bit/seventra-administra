import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';

import '../repositories/ubicacion_repository.dart';

/// Mueve un nodo hijo del árbol a otro padre, validando lo que
/// `UbicacionRepository.moverA` (mecánico) no valida: raíz inmóvil,
/// ciclos y profundidad máxima.
class MoverUbicacionUseCase {
  MoverUbicacionUseCase(this._repository);

  final UbicacionRepository _repository;

  static const _profundidadMaxima = 4;

  Future<Result<UbicacionData>> ejecutar({
    required String ubicacionId,
    required String nuevoParentId,
  }) async {
    if (ubicacionId == nuevoParentId) {
      return const Result.failure(ValidationFailure('Una ubicación no puede ser su propio padre.'));
    }

    final nodo = await _repository.obtenerPorId(ubicacionId);
    if (nodo == null) {
      return Result.failure(NotFoundFailure('Ubicación no encontrada: $ubicacionId'));
    }
    if (nodo.parentId == null) {
      return const Result.failure(
        ValidationFailure('No se puede mover un nodo raíz — su posición es fija durante toda la vida de su Sucursal/Servicio.'),
      );
    }

    final nuevoParent = await _repository.obtenerPorId(nuevoParentId);
    if (nuevoParent == null) {
      return Result.failure(NotFoundFailure('Ubicación destino no encontrada: $nuevoParentId'));
    }

    var profundidadNuevoParent = 1;
    var cursor = nuevoParent;
    while (cursor.parentId != null) {
      final siguienteId = cursor.parentId!;
      if (siguienteId == ubicacionId) {
        return const Result.failure(ValidationFailure('El movimiento crearía un ciclo.'));
      }
      profundidadNuevoParent++;
      final siguiente = await _repository.obtenerPorId(siguienteId);
      if (siguiente == null) break;
      cursor = siguiente;
    }

    if (profundidadNuevoParent + 1 > _profundidadMaxima) {
      return const Result.failure(
        ValidationFailure('La ubicación quedaría a más de $_profundidadMaxima niveles de profundidad.'),
      );
    }

    await _repository.moverA(ubicacionId: ubicacionId, nuevoParentId: nuevoParentId);
    final actualizado = await _repository.obtenerPorId(ubicacionId);
    return Result.ok(actualizado!);
  }
}
