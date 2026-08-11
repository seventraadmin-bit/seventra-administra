import '../repositories/articulo_repository.dart';

/// Resultado de la eliminación física extraordinaria de un
/// [ArticuloData] (Etapa 11D) — ver el doc comment de
/// `ArticuloRepositoryImpl.eliminarFisicamente` para las condiciones
/// exactas de elegibilidad.
sealed class EliminarArticuloFisicamenteResultado {}

class EliminarArticuloFisicamenteExitoso extends EliminarArticuloFisicamenteResultado {}

class EliminarArticuloFisicamenteNoExiste extends EliminarArticuloFisicamenteResultado {}

class EliminarArticuloFisicamenteMotivoRequerido extends EliminarArticuloFisicamenteResultado {}

/// El Artículo tiene variantes, unidades serializadas, asignaciones,
/// movimientos de inventario o partidas de Compra — no es un simple
/// error de captura, así que la eliminación física se rechaza siempre,
/// sin excepción.
class EliminarArticuloFisicamenteTieneDependencias extends EliminarArticuloFisicamenteResultado {
  EliminarArticuloFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

/// Reservado para la frontera de autorización (facultad Maestro-only,
/// Etapa 11D) — nunca lo produce el propio caso de uso.
class EliminarArticuloFisicamenteErrorInesperado extends EliminarArticuloFisicamenteResultado {
  EliminarArticuloFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Eliminación física extraordinaria de un Artículo (Etapa 11D) — la
/// única forma de borrado real de este dominio, exclusiva del Usuario
/// Maestro (verificado en la fachada de aplicación con
/// `exigirMaestro`, nunca aquí — este caso de uso es puro). `motivo`
/// siempre obligatorio, sin excepción. Toda la validación de
/// dependencias + snapshot + registro de auditoría + `DELETE` ocurre
/// transaccionalmente dentro de `ArticuloRepositoryImpl.eliminarFisicamente`
/// — este caso de uso solo valida `motivo` y traduce el resultado.
class EliminarArticuloFisicamenteUseCase {
  EliminarArticuloFisicamenteUseCase(this._repository);

  final ArticuloRepository _repository;

  Future<EliminarArticuloFisicamenteResultado> ejecutar({
    required String articuloId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return EliminarArticuloFisicamenteMotivoRequerido();

    try {
      return await _repository.eliminarFisicamente(
        articuloId: articuloId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarArticuloFisicamenteErrorInesperado(e.toString());
    }
  }
}
