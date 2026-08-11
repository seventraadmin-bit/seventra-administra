import '../repositories/puesto_repository.dart';

/// Resultado de la eliminación física extraordinaria de un
/// [PuestoData] (Etapa 11D) — ver el doc comment de
/// `PuestoRepositoryImpl.eliminarFisicamente` para las condiciones
/// exactas de elegibilidad.
sealed class EliminarPuestoFisicamenteResultado {}

class EliminarPuestoFisicamenteExitoso extends EliminarPuestoFisicamenteResultado {}

class EliminarPuestoFisicamenteNoExiste extends EliminarPuestoFisicamenteResultado {}

class EliminarPuestoFisicamenteMotivoRequerido extends EliminarPuestoFisicamenteResultado {}

/// El Puesto tiene vigencias comerciales, Usuarios o Empleados
/// registrados — no es un simple error de captura, así que la
/// eliminación física se rechaza siempre, sin excepción.
class EliminarPuestoFisicamenteTieneDependencias extends EliminarPuestoFisicamenteResultado {
  EliminarPuestoFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

/// Reservado para la frontera de autorización (facultad Maestro-only,
/// Etapa 11D) — nunca lo produce el propio caso de uso.
class EliminarPuestoFisicamenteErrorInesperado extends EliminarPuestoFisicamenteResultado {
  EliminarPuestoFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Eliminación física extraordinaria de un Puesto (Etapa 11D) — la
/// única forma de borrado real de este catálogo, exclusiva del Usuario
/// Maestro (verificado en la fachada de aplicación con
/// `exigirMaestro`, nunca aquí — este caso de uso es puro). `motivo`
/// siempre obligatorio, sin excepción. Toda la validación de
/// dependencias + snapshot + registro de auditoría + `DELETE` ocurre
/// transaccionalmente dentro de
/// `PuestoRepositoryImpl.eliminarFisicamente` — este caso de uso solo
/// valida `motivo` y traduce el resultado.
class EliminarPuestoFisicamenteUseCase {
  EliminarPuestoFisicamenteUseCase(this._repository);

  final PuestoRepository _repository;

  Future<EliminarPuestoFisicamenteResultado> ejecutar({
    required String puestoId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return EliminarPuestoFisicamenteMotivoRequerido();

    try {
      return await _repository.eliminarFisicamente(
        puestoId: puestoId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarPuestoFisicamenteErrorInesperado(e.toString());
    }
  }
}
