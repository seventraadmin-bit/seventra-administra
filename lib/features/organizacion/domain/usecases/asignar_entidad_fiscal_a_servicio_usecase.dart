import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import '../repositories/entidad_fiscal_repository.dart';
import '../repositories/servicio_repository.dart';

/// Resultado de [AsignarEntidadFiscalAServicioUseCase] — tipos propios
/// para que la pantalla muestre un mensaje específico, mismo patrón que
/// `CambiarEstatusServicioResultado`.
sealed class AsignarEntidadFiscalAServicioResultado {}

class AsignarEntidadFiscalAServicioExitoso extends AsignarEntidadFiscalAServicioResultado {
  AsignarEntidadFiscalAServicioExitoso(this.servicio);
  final ServicioData servicio;
}

/// La Entidad fiscal no existe o pertenece a un Cliente distinto del
/// Servicio.
class AsignarEntidadFiscalAServicioNoPerteneceAlCliente extends AsignarEntidadFiscalAServicioResultado {}

/// Solo posible al asignar una Entidad fiscal *nueva*: está archivada.
/// Una Entidad fiscal ya asignada que se archiva después nunca pasa por
/// aquí — la relación se conserva y el expediente solo advierte (ver
/// `ServicioExpedienteData.entidadFiscalArchivada`).
class AsignarEntidadFiscalAServicioNoDisponible extends AsignarEntidadFiscalAServicioResultado {}

class AsignarEntidadFiscalAServicioErrorInesperado extends AsignarEntidadFiscalAServicioResultado {
  AsignarEntidadFiscalAServicioErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Asigna o quita la Entidad fiscal de un Servicio — acción
/// independiente del formulario general de datos generales (Etapa
/// 4F.2, punto 1). `entidadFiscalId: null` siempre quita la asignación
/// sin ninguna validación (quitar nunca puede fallar por reglas de
/// negocio). Asignar una nueva sí exige pertenencia al mismo Cliente y
/// estar activa — ambas solo en el momento de la asignación, nunca
/// reevaluadas retroactivamente.
class AsignarEntidadFiscalAServicioUseCase {
  AsignarEntidadFiscalAServicioUseCase(this._servicioRepository, this._entidadFiscalRepository);

  final ServicioRepository _servicioRepository;
  final EntidadFiscalRepository _entidadFiscalRepository;

  Future<AsignarEntidadFiscalAServicioResultado> ejecutar({
    required String servicioId,
    required String? entidadFiscalId,
  }) async {
    if (entidadFiscalId == null) {
      try {
        final servicio = await _servicioRepository.asignarEntidadFiscal(
          servicioId: servicioId,
          entidadFiscalId: null,
        );
        return AsignarEntidadFiscalAServicioExitoso(servicio);
      } catch (e) {
        return AsignarEntidadFiscalAServicioErrorInesperado(e.toString());
      }
    }

    final servicioActual = await _servicioRepository.obtenerPorId(servicioId);
    if (servicioActual == null) {
      return AsignarEntidadFiscalAServicioErrorInesperado('Servicio no encontrado: $servicioId');
    }

    final entidad = await _entidadFiscalRepository.obtenerPorId(entidadFiscalId);
    if (entidad == null || entidad.clienteId != servicioActual.clienteId) {
      return AsignarEntidadFiscalAServicioNoPerteneceAlCliente();
    }
    if (entidad.cicloVidaRegistro != CicloVidaRegistro.activo.name) {
      return AsignarEntidadFiscalAServicioNoDisponible();
    }

    try {
      final servicio = await _servicioRepository.asignarEntidadFiscal(
        servicioId: servicioId,
        entidadFiscalId: entidadFiscalId,
      );
      return AsignarEntidadFiscalAServicioExitoso(servicio);
    } catch (e) {
      return AsignarEntidadFiscalAServicioErrorInesperado(e.toString());
    }
  }
}
