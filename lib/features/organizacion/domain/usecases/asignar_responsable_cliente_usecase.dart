import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import '../repositories/cliente_repository.dart';
import '../repositories/servicio_repository.dart';

/// Resultado de [AsignarResponsableClienteUseCase] — mismo patrón que
/// `AsignarEntidadFiscalAServicioResultado`.
sealed class AsignarResponsableClienteResultado {}

class AsignarResponsableClienteExitoso extends AsignarResponsableClienteResultado {
  AsignarResponsableClienteExitoso(this.servicio);
  final ServicioData servicio;
}

/// El Contacto no existe o pertenece a un Cliente distinto del Servicio.
class AsignarResponsableClienteNoPerteneceAlCliente extends AsignarResponsableClienteResultado {}

/// Solo posible al asignar un Contacto *nuevo*: está archivado.
class AsignarResponsableClienteNoDisponible extends AsignarResponsableClienteResultado {}

class AsignarResponsableClienteErrorInesperado extends AsignarResponsableClienteResultado {
  AsignarResponsableClienteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Asigna o quita el Contacto responsable del Cliente en un Servicio —
/// acción independiente (Etapa 4F.2, punto 1). Puede ser un Contacto
/// `comercial` u `operativo`, sin restricción por tipo. `contactoId:
/// null` siempre quita la asignación.
class AsignarResponsableClienteUseCase {
  AsignarResponsableClienteUseCase(this._servicioRepository, this._clienteRepository);

  final ServicioRepository _servicioRepository;
  final ClienteRepository _clienteRepository;

  Future<AsignarResponsableClienteResultado> ejecutar({
    required String servicioId,
    required String? contactoId,
    String? actorUsuarioId,
  }) async {
    if (contactoId == null) {
      try {
        final servicio = await _servicioRepository.asignarResponsableCliente(
          servicioId: servicioId,
          contactoId: null,
          actorUsuarioId: actorUsuarioId,
        );
        return AsignarResponsableClienteExitoso(servicio);
      } catch (e) {
        return AsignarResponsableClienteErrorInesperado(e.toString());
      }
    }

    final servicioActual = await _servicioRepository.obtenerPorId(servicioId);
    if (servicioActual == null) {
      return AsignarResponsableClienteErrorInesperado('Servicio no encontrado: $servicioId');
    }

    final contacto = await _clienteRepository.obtenerContactoPorId(contactoId);
    if (contacto == null || contacto.clienteId != servicioActual.clienteId) {
      return AsignarResponsableClienteNoPerteneceAlCliente();
    }
    if (contacto.cicloVidaRegistro != CicloVidaRegistro.activo.name) {
      return AsignarResponsableClienteNoDisponible();
    }

    try {
      final servicio = await _servicioRepository.asignarResponsableCliente(
        servicioId: servicioId,
        contactoId: contactoId,
        actorUsuarioId: actorUsuarioId,
      );
      return AsignarResponsableClienteExitoso(servicio);
    } catch (e) {
      return AsignarResponsableClienteErrorInesperado(e.toString());
    }
  }
}
