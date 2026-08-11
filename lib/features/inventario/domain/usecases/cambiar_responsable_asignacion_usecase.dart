import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/asignacion_repository.dart';

sealed class CambiarResponsableAsignacionResultado {}

class CambiarResponsableAsignacionExitoso extends CambiarResponsableAsignacionResultado {
  CambiarResponsableAsignacionExitoso(this.nueva);
  final AsignacionData nueva;
}

class CambiarResponsableAsignacionNoExiste extends CambiarResponsableAsignacionResultado {}

class CambiarResponsableAsignacionNoVigente extends CambiarResponsableAsignacionResultado {}

/// Alcance de la Etapa 9D, deliberadamente acotado: "cambiar
/// responsable" solo aplica a unidades serializadas (`unidadId` no
/// nulo) — el caso que Marlon pidió resolver (teléfono físico). Un
/// Artículo por cantidad no tiene identidad individual que "seguir"
/// entre un responsable y otro; extenderlo ahí queda para cuando exista
/// un caso real que lo justifique.
class CambiarResponsableAsignacionSoloUnidadesSerializadas extends CambiarResponsableAsignacionResultado {}

class CambiarResponsableAsignacionDestinoInvalido extends CambiarResponsableAsignacionResultado {}

class CambiarResponsableAsignacionMismoResponsable extends CambiarResponsableAsignacionResultado {}

class CambiarResponsableAsignacionFechaInvalida extends CambiarResponsableAsignacionResultado {}

class CambiarResponsableAsignacionErrorInesperado extends CambiarResponsableAsignacionResultado {
  CambiarResponsableAsignacionErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cambia quién es responsable del MISMO bien (Etapa 9D, ajuste
/// aprobado por Marlon tras el cierre inicial) — distinto de
/// `ReemplazarAsignacionUseCase` (cambia el bien físico) y de
/// `CerrarAsignacionUseCase`+`CrearAsignacionUseCase` (que generan una
/// devolución y una salida reales de Inventario). El bien nunca pasa
/// por `MovimientoInventario`, nunca cambia `ArticuloUnidad.estatus` —
/// la custodia se mantiene, solo cambia el titular.
class CambiarResponsableAsignacionUseCase {
  CambiarResponsableAsignacionUseCase(this._repository);

  final AsignacionRepository _repository;

  Future<CambiarResponsableAsignacionResultado> ejecutar({
    required String asignacionId,
    String? nuevoEmpleadoId,
    String? nuevoServicioId,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    final actual = await _repository.obtenerPorId(asignacionId);
    if (actual == null) return CambiarResponsableAsignacionNoExiste();
    if (actual.estatus != 'activa') return CambiarResponsableAsignacionNoVigente();
    if (actual.unidadId == null) return CambiarResponsableAsignacionSoloUnidadesSerializadas();

    final destinoValido = (nuevoEmpleadoId != null) != (nuevoServicioId != null);
    if (!destinoValido) return CambiarResponsableAsignacionDestinoInvalido();

    if (nuevoEmpleadoId != null && nuevoEmpleadoId == actual.empleadoId) {
      return CambiarResponsableAsignacionMismoResponsable();
    }
    if (nuevoServicioId != null && nuevoServicioId == actual.servicioId) {
      return CambiarResponsableAsignacionMismoResponsable();
    }

    if (fecha.isBefore(actual.fechaEntrega)) return CambiarResponsableAsignacionFechaInvalida();

    try {
      final nueva = await _repository.cambiarResponsable(
        asignacionId: asignacionId,
        nuevoEmpleadoId: nuevoEmpleadoId,
        nuevoServicioId: nuevoServicioId,
        fecha: fecha,
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );
      return CambiarResponsableAsignacionExitoso(nueva);
    } catch (e) {
      return CambiarResponsableAsignacionErrorInesperado(e.toString());
    }
  }
}
