import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';

import '../repositories/sucursal_repository.dart';
import 'sucursal_expediente_data.dart';

/// Ensambla el expediente completo de una Sucursal (Sucursal + Dirección
/// principal + Horario) — mismo patrón que
/// `ObtenerExpedienteEmpresaUseCase`.
class ObtenerExpedienteSucursalUseCase {
  ObtenerExpedienteSucursalUseCase(this._repository);

  final SucursalRepository _repository;

  Future<Result<SucursalExpedienteData>> ejecutar(String sucursalId) async {
    final sucursal = await _repository.obtenerPorId(sucursalId);
    if (sucursal == null) {
      return Result.failure(NotFoundFailure('Sucursal no encontrada: $sucursalId'));
    }

    final direccion = await _repository.obtenerDireccionPrincipal(sucursalId);
    final horario = await _repository.obtenerHorario(sucursalId);

    return Result.ok(
      SucursalExpedienteData(sucursal: sucursal, direccionPrincipal: direccion, horario: horario),
    );
  }
}
