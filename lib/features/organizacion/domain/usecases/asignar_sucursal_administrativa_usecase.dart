import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import '../repositories/servicio_repository.dart';
import '../repositories/sucursal_repository.dart';

/// Resultado de [AsignarSucursalAdministrativaUseCase] — mismo patrón
/// que `AsignarEntidadFiscalAServicioResultado`.
sealed class AsignarSucursalAdministrativaResultado {}

class AsignarSucursalAdministrativaExitoso extends AsignarSucursalAdministrativaResultado {
  AsignarSucursalAdministrativaExitoso(this.servicio);
  final ServicioData servicio;
}

/// La Sucursal no existe.
class AsignarSucursalAdministrativaNoExiste extends AsignarSucursalAdministrativaResultado {}

/// Solo posible al asignar una Sucursal *nueva*: está archivada.
class AsignarSucursalAdministrativaNoDisponible extends AsignarSucursalAdministrativaResultado {}

class AsignarSucursalAdministrativaErrorInesperado extends AsignarSucursalAdministrativaResultado {
  AsignarSucursalAdministrativaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Asigna o quita la Sucursal administrativa de un Servicio — acción
/// independiente (Etapa 4F.2, punto 1). Sin dependencia del Cliente (a
/// diferencia de Entidad fiscal/Responsable del Cliente): una Sucursal
/// es interna a RISEG. `sucursalId: null` siempre quita la asignación.
class AsignarSucursalAdministrativaUseCase {
  AsignarSucursalAdministrativaUseCase(this._servicioRepository, this._sucursalRepository);

  final ServicioRepository _servicioRepository;
  final SucursalRepository _sucursalRepository;

  Future<AsignarSucursalAdministrativaResultado> ejecutar({
    required String servicioId,
    required String? sucursalId,
    String? actorUsuarioId,
  }) async {
    if (sucursalId == null) {
      try {
        final servicio = await _servicioRepository.asignarSucursalAdministrativa(
          servicioId: servicioId,
          sucursalId: null,
          actorUsuarioId: actorUsuarioId,
        );
        return AsignarSucursalAdministrativaExitoso(servicio);
      } catch (e) {
        return AsignarSucursalAdministrativaErrorInesperado(e.toString());
      }
    }

    final sucursal = await _sucursalRepository.obtenerPorId(sucursalId);
    if (sucursal == null) {
      return AsignarSucursalAdministrativaNoExiste();
    }
    if (sucursal.cicloVidaRegistro != CicloVidaRegistro.activo.name) {
      return AsignarSucursalAdministrativaNoDisponible();
    }

    try {
      final servicio = await _servicioRepository.asignarSucursalAdministrativa(
        servicioId: servicioId,
        sucursalId: sucursalId,
        actorUsuarioId: actorUsuarioId,
      );
      return AsignarSucursalAdministrativaExitoso(servicio);
    } catch (e) {
      return AsignarSucursalAdministrativaErrorInesperado(e.toString());
    }
  }
}
