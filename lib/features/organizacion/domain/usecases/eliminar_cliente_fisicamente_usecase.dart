import '../repositories/cliente_repository.dart';

/// Resultado de la eliminación física extraordinaria de un
/// [ClienteData] (Etapa 15) — ver el doc comment de
/// `ClienteRepositoryImpl.eliminarFisicamente` para las condiciones
/// exactas de elegibilidad.
sealed class EliminarClienteFisicamenteResultado {}

class EliminarClienteFisicamenteExitoso extends EliminarClienteFisicamenteResultado {}

class EliminarClienteFisicamenteNoExiste extends EliminarClienteFisicamenteResultado {}

class EliminarClienteFisicamenteMotivoRequerido extends EliminarClienteFisicamenteResultado {}

/// El Cliente tiene Servicios, Contactos, Entidades fiscales, Pagos (o
/// cualquier otra dependencia real descubierta en el grafo de FK)
/// registrados — no es un simple error de captura, así que la
/// eliminación física se rechaza siempre, sin excepción.
class EliminarClienteFisicamenteTieneDependencias extends EliminarClienteFisicamenteResultado {
  EliminarClienteFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

/// Reservado para la frontera de autorización (facultad Maestro-only,
/// Etapa 11D) — nunca lo produce el propio caso de uso.
class EliminarClienteFisicamenteErrorInesperado extends EliminarClienteFisicamenteResultado {
  EliminarClienteFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Eliminación física extraordinaria de un Cliente (Etapa 15, mismo
/// patrón que la Etapa 11D) — exclusiva del Usuario Maestro
/// (verificado en la fachada de aplicación con `exigirMaestro`, nunca
/// aquí — este caso de uso es puro). `motivo` siempre obligatorio, sin
/// excepción. Toda la validación de dependencias + snapshot + registro
/// de auditoría + `DELETE` ocurre transaccionalmente dentro de
/// `ClienteRepositoryImpl.eliminarFisicamente` — este caso de uso solo
/// valida `motivo` y traduce el resultado.
class EliminarClienteFisicamenteUseCase {
  EliminarClienteFisicamenteUseCase(this._repository);

  final ClienteRepository _repository;

  Future<EliminarClienteFisicamenteResultado> ejecutar({
    required String clienteId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return EliminarClienteFisicamenteMotivoRequerido();

    try {
      return await _repository.eliminarFisicamente(
        clienteId: clienteId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarClienteFisicamenteErrorInesperado(e.toString());
    }
  }
}
