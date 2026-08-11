import '../repositories/area_repository.dart';

/// Resultado de la eliminación física extraordinaria de un [AreaData]
/// (Etapa 11D) — ver el doc comment de
/// `AreaRepositoryImpl.eliminarFisicamente` para las condiciones
/// exactas de elegibilidad.
sealed class EliminarAreaFisicamenteResultado {}

class EliminarAreaFisicamenteExitoso extends EliminarAreaFisicamenteResultado {}

class EliminarAreaFisicamenteNoExiste extends EliminarAreaFisicamenteResultado {}

class EliminarAreaFisicamenteMotivoRequerido extends EliminarAreaFisicamenteResultado {}

/// El Área tiene Puestos (o cualquier otra dependencia real
/// descubierta en el grafo de FK) registrados — no es un simple error
/// de captura, así que la eliminación física se rechaza siempre, sin
/// excepción.
class EliminarAreaFisicamenteTieneDependencias extends EliminarAreaFisicamenteResultado {
  EliminarAreaFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

/// Reservado para la frontera de autorización (facultad Maestro-only,
/// Etapa 11D) — nunca lo produce el propio caso de uso.
class EliminarAreaFisicamenteErrorInesperado extends EliminarAreaFisicamenteResultado {
  EliminarAreaFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Eliminación física extraordinaria de un Área (Etapa 11D) — la única
/// forma de borrado real de este catálogo, exclusiva del Usuario
/// Maestro (verificado en la fachada de aplicación con
/// `exigirMaestro`, nunca aquí — este caso de uso es puro). `motivo`
/// siempre obligatorio, sin excepción. Toda la validación de
/// dependencias + snapshot + registro de auditoría + `DELETE` ocurre
/// transaccionalmente dentro de `AreaRepositoryImpl.eliminarFisicamente`
/// — este caso de uso solo valida `motivo` y traduce el resultado.
class EliminarAreaFisicamenteUseCase {
  EliminarAreaFisicamenteUseCase(this._repository);

  final AreaRepository _repository;

  Future<EliminarAreaFisicamenteResultado> ejecutar({
    required String areaId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return EliminarAreaFisicamenteMotivoRequerido();

    try {
      return await _repository.eliminarFisicamente(
        areaId: areaId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarAreaFisicamenteErrorInesperado(e.toString());
    }
  }
}
