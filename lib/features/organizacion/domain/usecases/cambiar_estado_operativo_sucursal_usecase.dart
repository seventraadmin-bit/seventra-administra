import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/features/organizacion/data/tables/sucursal_table.dart';

import '../repositories/sucursal_repository.dart';

/// Transición de negocio explícita ("Cerrar temporalmente"/"Reabrir") —
/// nunca un campo silencioso del formulario de edición. La pantalla pide
/// confirmación (`RisegDialog.showConfirmation`) antes de invocar esto.
class CambiarEstadoOperativoSucursalUseCase {
  CambiarEstadoOperativoSucursalUseCase(this._repository);

  final SucursalRepository _repository;

  Future<Result<SucursalData>> ejecutar({
    required String sucursalId,
    required EstadoOperativoSucursal nuevo,
  }) async {
    final actualizada = await _repository.cambiarEstadoOperativo(sucursalId: sucursalId, nuevo: nuevo);
    return Result.ok(actualizada);
  }
}
