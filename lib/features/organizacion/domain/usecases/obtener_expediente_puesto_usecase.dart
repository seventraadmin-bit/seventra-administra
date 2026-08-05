import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';

import '../repositories/puesto_repository.dart';

/// Más simple que el de Sucursal: Puesto no tiene sub-entidades que
/// ensamblar (sin dirección, sin horario), así que `PuestoData` en sí
/// ya es el expediente completo.
class ObtenerExpedientePuestoUseCase {
  ObtenerExpedientePuestoUseCase(this._repository);

  final PuestoRepository _repository;

  Future<Result<PuestoData>> ejecutar(String puestoId) async {
    final puesto = await _repository.obtenerPorId(puestoId);
    if (puesto == null) {
      return Result.failure(NotFoundFailure('Puesto no encontrado: $puestoId'));
    }
    return Result.ok(puesto);
  }
}
