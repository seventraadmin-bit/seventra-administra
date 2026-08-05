import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';

import '../repositories/servicio_repository.dart';
import 'servicio_expediente_data.dart';

/// Ensambla el expediente de un Servicio (Servicio + si ya tiene
/// Dirección operativa activa) — mismo patrón que
/// `ObtenerExpedienteClienteUseCase`.
class ObtenerExpedienteServicioUseCase {
  ObtenerExpedienteServicioUseCase(this._repository);

  final ServicioRepository _repository;

  Future<Result<ServicioExpedienteData>> ejecutar(String servicioId) async {
    final servicio = await _repository.obtenerPorId(servicioId);
    if (servicio == null) {
      return Result.failure(NotFoundFailure('Servicio no encontrado: $servicioId'));
    }

    final tieneDireccion = await _repository.tieneDireccionOperativaActiva(servicioId);

    return Result.ok(
      ServicioExpedienteData(servicio: servicio, tieneDireccionOperativaActiva: tieneDireccion),
    );
  }
}
