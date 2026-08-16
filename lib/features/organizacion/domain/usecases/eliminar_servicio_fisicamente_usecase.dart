import '../repositories/servicio_repository.dart';

/// Resultado de la eliminación física extraordinaria de un
/// [ServicioData] (Etapa 15) — ver el doc comment de
/// `ServicioRepositoryImpl.eliminarFisicamente` para las condiciones
/// exactas de elegibilidad.
sealed class EliminarServicioFisicamenteResultado {}

class EliminarServicioFisicamenteExitoso extends EliminarServicioFisicamenteResultado {}

class EliminarServicioFisicamenteNoExiste extends EliminarServicioFisicamenteResultado {}

class EliminarServicioFisicamenteMotivoRequerido extends EliminarServicioFisicamenteResultado {}

/// El Servicio tiene Personal asignado, Configuración comercial/de
/// cobro, movimientos financieros (o cualquier otra dependencia real
/// descubierta en el grafo de FK) registrados — no es un simple error
/// de captura, así que la eliminación física se rechaza siempre, sin
/// excepción.
class EliminarServicioFisicamenteTieneDependencias extends EliminarServicioFisicamenteResultado {
  EliminarServicioFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

/// Reservado para la frontera de autorización (facultad Maestro-only,
/// Etapa 11D) — nunca lo produce el propio caso de uso.
class EliminarServicioFisicamenteErrorInesperado extends EliminarServicioFisicamenteResultado {
  EliminarServicioFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Eliminación física extraordinaria de un Servicio (Etapa 15, mismo
/// patrón que la Etapa 11D) — exclusiva del Usuario Maestro
/// (verificado en la fachada de aplicación con `exigirMaestro`, nunca
/// aquí — este caso de uso es puro). `motivo` siempre obligatorio, sin
/// excepción. Toda la validación de dependencias + snapshot + registro
/// de auditoría + `DELETE` ocurre transaccionalmente dentro de
/// `ServicioRepositoryImpl.eliminarFisicamente` — este caso de uso
/// solo valida `motivo` y traduce el resultado.
class EliminarServicioFisicamenteUseCase {
  EliminarServicioFisicamenteUseCase(this._repository);

  final ServicioRepository _repository;

  Future<EliminarServicioFisicamenteResultado> ejecutar({
    required String servicioId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return EliminarServicioFisicamenteMotivoRequerido();

    try {
      return await _repository.eliminarFisicamente(
        servicioId: servicioId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarServicioFisicamenteErrorInesperado(e.toString());
    }
  }
}
