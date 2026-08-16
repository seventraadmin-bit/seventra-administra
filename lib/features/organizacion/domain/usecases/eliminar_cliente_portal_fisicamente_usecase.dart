import '../repositories/cliente_portal_repository.dart';

/// Resultado de la eliminación física extraordinaria de un
/// [ClientePortalData] (Etapa 15) — ver el doc comment de
/// `ClientePortalRepositoryImpl.eliminarFisicamente` para las
/// condiciones exactas de elegibilidad. Mismo patrón que
/// `EliminarPuestoFisicamenteResultado` (Etapa 11D).
sealed class EliminarClientePortalFisicamenteResultado {}

class EliminarClientePortalFisicamenteExitoso extends EliminarClientePortalFisicamenteResultado {}

class EliminarClientePortalFisicamenteNoExiste extends EliminarClientePortalFisicamenteResultado {}

class EliminarClientePortalFisicamenteMotivoRequerido extends EliminarClientePortalFisicamenteResultado {}

/// El portal está referenciado por al menos una `ConfiguracionCobroVigencia`
/// o `DocumentoPorEmitir` — el histórico debe seguir siendo resoluble,
/// así que la eliminación física se rechaza siempre, sin excepción.
/// Archivar sí sigue permitido en este caso (ver
/// `CambiarCicloVidaClientePortalUseCase`).
class EliminarClientePortalFisicamenteTieneDependencias extends EliminarClientePortalFisicamenteResultado {
  EliminarClientePortalFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

/// Reservado para la frontera de autorización (facultad Maestro-only,
/// Etapa 11D) — nunca lo produce el propio caso de uso.
class EliminarClientePortalFisicamenteErrorInesperado extends EliminarClientePortalFisicamenteResultado {
  EliminarClientePortalFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Eliminación física extraordinaria de un portal del Cliente (Etapa
/// 15) — la única forma de borrado real, exclusiva del Usuario Maestro
/// (verificado en la fachada de aplicación con `exigirMaestro`, nunca
/// aquí — este caso de uso es puro). `motivo` siempre obligatorio, sin
/// excepción. Toda la validación de dependencias + snapshot + registro
/// de auditoría + `DELETE` ocurre transaccionalmente dentro de
/// `ClientePortalRepositoryImpl.eliminarFisicamente` — este caso de uso
/// solo valida `motivo` y traduce el resultado.
class EliminarClientePortalFisicamenteUseCase {
  EliminarClientePortalFisicamenteUseCase(this._repository);

  final ClientePortalRepository _repository;

  Future<EliminarClientePortalFisicamenteResultado> ejecutar({
    required String clientePortalId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return EliminarClientePortalFisicamenteMotivoRequerido();

    try {
      return await _repository.eliminarFisicamente(
        id: clientePortalId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarClientePortalFisicamenteErrorInesperado(e.toString());
    }
  }
}
