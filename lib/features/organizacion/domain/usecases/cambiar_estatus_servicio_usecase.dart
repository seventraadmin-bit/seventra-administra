import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';

import '../repositories/cliente_repository.dart';
import '../repositories/servicio_repository.dart';

/// Resultado de [CambiarEstatusServicioUseCase] — tipos distintos por
/// cada regla de la Etapa 4F.1, para que la pantalla pueda mostrar un
/// mensaje específico en vez de un error genérico.
sealed class CambiarEstatusServicioResultado {}

class CambiarEstatusServicioExitoso extends CambiarEstatusServicioResultado {
  CambiarEstatusServicioExitoso(this.servicio);
  final ServicioData servicio;
}

/// La transición solicitada no está permitida desde el estatus actual
/// (ver la tabla de transiciones en [CambiarEstatusServicioUseCase]).
class CambiarEstatusServicioTransicionInvalida extends CambiarEstatusServicioResultado {}

/// Solo posible al intentar pasar a `activo`: el Cliente propietario ya
/// no existe o está archivado/baja/borradoLogico.
class CambiarEstatusServicioClienteNoDisponible extends CambiarEstatusServicioResultado {}

/// Solo posible al intentar pasar a `activo`: no existe una Dirección
/// operativa activa para este Servicio. Inalcanzable en la práctica
/// durante toda la Etapa 4F.1, porque la captura de Dirección llega
/// hasta la 4F.2 — documentado, no un error de implementación.
class CambiarEstatusServicioFaltaDireccionOperativa extends CambiarEstatusServicioResultado {}

/// Solo posible al terminar: no existe `fechaTermino` previa y tampoco
/// se proporcionó una fecha efectiva en la misma acción.
class CambiarEstatusServicioRequiereFechaTermino extends CambiarEstatusServicioResultado {}

/// Solo posible al terminar: la fecha efectiva proporcionada es anterior
/// a `fechaInicio`.
class CambiarEstatusServicioFechaTerminoInvalida extends CambiarEstatusServicioResultado {}

class CambiarEstatusServicioErrorInesperado extends CambiarEstatusServicioResultado {
  CambiarEstatusServicioErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cambia el estatus comercial de un Servicio — con una máquina de
/// transiciones deliberadamente ni rígida ni libre (punto 6 de la
/// aprobación de la Etapa 4F.1): cada estatus solo puede avanzar hacia
/// un subconjunto concreto del siguiente, y `terminado → activo` exige
/// además la acción explícita de "Reactivar" (misma llamada, mismas
/// validaciones — la distinción es de UI, no de este caso de uso).
///
/// Suspender nunca requiere Dirección operativa ni Cliente disponible —
/// solo activar (incluida la reactivación desde terminado) lo exige,
/// y durante 4F.1 eso significa que ningún Servicio puede llegar a
/// `activo` todavía: la captura de Dirección es de la Etapa 4F.2. Esto
/// es intencional, cubierto por su propia prueba.
class CambiarEstatusServicioUseCase {
  CambiarEstatusServicioUseCase(this._repository, this._clienteRepository);

  final ServicioRepository _repository;
  final ClienteRepository _clienteRepository;

  static const _transicionesPermitidas = {
    EstatusServicio.cotizado: {EstatusServicio.activo, EstatusServicio.suspendido, EstatusServicio.terminado},
    EstatusServicio.activo: {EstatusServicio.suspendido, EstatusServicio.terminado},
    EstatusServicio.suspendido: {EstatusServicio.activo, EstatusServicio.terminado},
    EstatusServicio.terminado: {EstatusServicio.activo},
  };

  Future<CambiarEstatusServicioResultado> ejecutar({
    required String servicioId,
    required EstatusServicio nuevo,
    DateTime? fechaTerminoEfectiva,
  }) async {
    final servicio = await _repository.obtenerPorId(servicioId);
    if (servicio == null) {
      return CambiarEstatusServicioErrorInesperado('Servicio no encontrado: $servicioId');
    }

    final actual = EstatusServicio.values.byName(servicio.estatus);
    final permitido = _transicionesPermitidas[actual]?.contains(nuevo) ?? false;
    if (!permitido) {
      return CambiarEstatusServicioTransicionInvalida();
    }

    if (nuevo == EstatusServicio.activo) {
      final cliente = await _clienteRepository.obtenerPorId(servicio.clienteId);
      if (cliente == null || cliente.cicloVidaRegistro != CicloVidaRegistro.activo.name) {
        return CambiarEstatusServicioClienteNoDisponible();
      }
      final tieneDireccion = await _repository.tieneDireccionOperativaActiva(servicioId);
      if (!tieneDireccion) {
        return CambiarEstatusServicioFaltaDireccionOperativa();
      }
    }

    DateTime? fechaTerminoFinal = servicio.fechaTermino;
    if (nuevo == EstatusServicio.terminado) {
      fechaTerminoFinal ??= fechaTerminoEfectiva;
      if (fechaTerminoFinal == null) {
        return CambiarEstatusServicioRequiereFechaTermino();
      }
      if (fechaTerminoFinal.isBefore(servicio.fechaInicio)) {
        return CambiarEstatusServicioFechaTerminoInvalida();
      }
    }

    try {
      final actualizado = await _repository.cambiarEstatus(
        id: servicioId,
        nuevo: nuevo,
        fechaTermino: fechaTerminoFinal,
      );
      return CambiarEstatusServicioExitoso(actualizado);
    } catch (e) {
      return CambiarEstatusServicioErrorInesperado(e.toString());
    }
  }
}
