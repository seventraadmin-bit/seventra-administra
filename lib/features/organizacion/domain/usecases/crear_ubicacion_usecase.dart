import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/features/organizacion/data/tables/ubicacion_table.dart';

import '../repositories/ubicacion_repository.dart';

/// Crea un nodo *hijo* del árbol de ubicaciones (nunca una raíz — las
/// raíces las crea `CrearSucursalUseCase`/`CrearServicioUseCase` junto
/// con su dueño). Valida que no se exceda la profundidad máxima antes de
/// solicitar el código.
class CrearUbicacionUseCase {
  CrearUbicacionUseCase(this._repository, this._generarCodigo);

  final UbicacionRepository _repository;
  final GenerarCodigoUseCase _generarCodigo;

  static const _profundidadMaxima = 4;

  Future<Result<UbicacionData>> ejecutar({
    required String nombre,
    required TipoUbicacion tipo,
    required String parentId,
  }) async {
    final parent = await _repository.obtenerPorId(parentId);
    if (parent == null) {
      return Result.failure(NotFoundFailure('Ubicación padre no encontrada: $parentId'));
    }

    var profundidadParent = 1;
    var cursor = parent;
    while (cursor.parentId != null) {
      profundidadParent++;
      final siguiente = await _repository.obtenerPorId(cursor.parentId!);
      if (siguiente == null) break;
      cursor = siguiente;
    }
    if (profundidadParent + 1 > _profundidadMaxima) {
      return const Result.failure(
        ValidationFailure('Ya se alcanzó la profundidad máxima de $_profundidadMaxima niveles.'),
      );
    }

    final codigoResult = await _generarCodigo.ejecutar('ubicacion');
    final String codigo;
    switch (codigoResult) {
      case Ok<String>(value: final v):
        codigo = v;
      case Err<String>(failure: final f):
        return Result.failure(f);
    }

    final nueva = await _repository.crearHijo(
      codigo: codigo,
      nombre: nombre,
      tipo: tipo,
      parentId: parentId,
    );
    return Result.ok(nueva);
  }
}
