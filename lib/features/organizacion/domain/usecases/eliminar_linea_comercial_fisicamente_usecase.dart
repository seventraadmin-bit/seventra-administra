import '../repositories/servicio_comercial_repository.dart';

/// Resultado de la eliminación física extraordinaria de una línea
/// comercial (Etapa 15, mismo patrón que la Etapa 11D) — ver el doc
/// comment de `ServicioComercialRepositoryImpl.eliminarFisicamente`
/// para las condiciones exactas de elegibilidad.
sealed class EliminarLineaComercialFisicamenteResultado {}

class EliminarLineaComercialFisicamenteExitoso extends EliminarLineaComercialFisicamenteResultado {}

class EliminarLineaComercialFisicamenteNoExiste extends EliminarLineaComercialFisicamenteResultado {}

class EliminarLineaComercialFisicamenteMotivoRequerido extends EliminarLineaComercialFisicamenteResultado {}

/// La línea ya tiene más de una vigencia o su única vigencia ya generó
/// un documento de Agenda — no es un simple error de captura, así que
/// la eliminación física se rechaza siempre, sin excepción.
class EliminarLineaComercialFisicamenteTieneDependencias extends EliminarLineaComercialFisicamenteResultado {
  EliminarLineaComercialFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

/// Reservado para la frontera de autorización (facultad Maestro-only) —
/// nunca lo produce el propio caso de uso.
class EliminarLineaComercialFisicamenteErrorInesperado extends EliminarLineaComercialFisicamenteResultado {
  EliminarLineaComercialFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Eliminación física extraordinaria de una línea comercial (Etapa 15)
/// — exclusiva del Usuario Maestro (`exigirMaestro`, nunca aquí — este
/// caso de uso es puro). `motivo` siempre obligatorio. Toda la
/// validación de dependencias + snapshot + registro de auditoría +
/// `DELETE` ocurre transaccionalmente dentro de
/// `ServicioComercialRepositoryImpl.eliminarFisicamente`.
class EliminarLineaComercialFisicamenteUseCase {
  EliminarLineaComercialFisicamenteUseCase(this._repository);

  final ServicioComercialRepository _repository;

  Future<EliminarLineaComercialFisicamenteResultado> ejecutar({
    required String lineaComercialId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return EliminarLineaComercialFisicamenteMotivoRequerido();

    try {
      return await _repository.eliminarFisicamente(
        lineaComercialId: lineaComercialId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarLineaComercialFisicamenteErrorInesperado(e.toString());
    }
  }
}
