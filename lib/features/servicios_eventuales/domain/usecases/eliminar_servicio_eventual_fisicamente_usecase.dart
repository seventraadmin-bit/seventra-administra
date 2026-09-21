import '../repositories/servicio_eventual_repository.dart';

/// Resultado de la eliminación física extraordinaria de un
/// [ServicioEventualData] (Etapa 11D) — ver el doc comment de
/// `ServicioEventualRepositoryImpl.eliminarFisicamente` para las
/// condiciones exactas de elegibilidad.
sealed class EliminarServicioEventualFisicamenteResultado {}

class EliminarServicioEventualFisicamenteExitoso extends EliminarServicioEventualFisicamenteResultado {}

class EliminarServicioEventualFisicamenteNoExiste extends EliminarServicioEventualFisicamenteResultado {}

class EliminarServicioEventualFisicamenteMotivoRequerido extends EliminarServicioEventualFisicamenteResultado {}

/// El eventual dejó huella financiera real (un Egreso emitido o un
/// cargo vivo en una tarjeta) o ya tiene cobranza asociada. Eso no es
/// un error de captura, así que la eliminación física se rechaza
/// siempre.
class EliminarServicioEventualFisicamenteTieneDependencias
    extends EliminarServicioEventualFisicamenteResultado {
  EliminarServicioEventualFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

/// Reservado para la frontera de autorización (facultad Maestro-only,
/// Etapa 11D) — nunca lo produce el propio caso de uso.
class EliminarServicioEventualFisicamenteErrorInesperado
    extends EliminarServicioEventualFisicamenteResultado {
  EliminarServicioEventualFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Eliminación física extraordinaria de un Servicio Eventual — la
/// única forma de borrado real de este dominio, exclusiva del Usuario
/// Maestro (verificado en la fachada de aplicación con `exigirMaestro`,
/// nunca aquí: este caso de uso es puro).
class EliminarServicioEventualFisicamenteUseCase {
  EliminarServicioEventualFisicamenteUseCase(this._repository);

  final ServicioEventualRepository _repository;

  Future<EliminarServicioEventualFisicamenteResultado> ejecutar({
    required String servicioEventualId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return EliminarServicioEventualFisicamenteMotivoRequerido();

    try {
      return await _repository.eliminarFisicamente(
        servicioEventualId: servicioEventualId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarServicioEventualFisicamenteErrorInesperado(e.toString());
    }
  }
}
