import '../repositories/linea_telefonica_repository.dart';

/// Resultado de la eliminación física extraordinaria de una
/// [LineaTelefonicaData] (Etapa 11D) — ver el doc comment de
/// `LineaTelefonicaRepositoryImpl.eliminarFisicamente` para las
/// condiciones exactas de elegibilidad.
sealed class EliminarLineaTelefonicaFisicamenteResultado {}

class EliminarLineaTelefonicaFisicamenteExitoso extends EliminarLineaTelefonicaFisicamenteResultado {}

class EliminarLineaTelefonicaFisicamenteNoExiste extends EliminarLineaTelefonicaFisicamenteResultado {}

class EliminarLineaTelefonicaFisicamenteMotivoRequerido extends EliminarLineaTelefonicaFisicamenteResultado {}

/// La línea tiene asignaciones, equipo asociado o recargas registradas
/// — no es un simple error de captura, así que la eliminación física se
/// rechaza siempre, sin excepción.
class EliminarLineaTelefonicaFisicamenteTieneDependencias extends EliminarLineaTelefonicaFisicamenteResultado {
  EliminarLineaTelefonicaFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

/// Reservado para la frontera de autorización (facultad Maestro-only,
/// Etapa 11D) — nunca lo produce el propio caso de uso.
class EliminarLineaTelefonicaFisicamenteErrorInesperado extends EliminarLineaTelefonicaFisicamenteResultado {
  EliminarLineaTelefonicaFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Eliminación física extraordinaria de una LineaTelefonica (Etapa
/// 11D) — la única forma de borrado real de este dominio, exclusiva del
/// Usuario Maestro (verificado en la fachada de aplicación con
/// `exigirMaestro`, nunca aquí — este caso de uso es puro). `motivo`
/// siempre obligatorio, sin excepción. Toda la validación de
/// dependencias + snapshot + registro de auditoría + `DELETE` ocurre
/// transaccionalmente dentro de
/// `LineaTelefonicaRepositoryImpl.eliminarFisicamente` — este caso de
/// uso solo valida `motivo` y traduce el resultado.
class EliminarLineaTelefonicaFisicamenteUseCase {
  EliminarLineaTelefonicaFisicamenteUseCase(this._repository);

  final LineaTelefonicaRepository _repository;

  Future<EliminarLineaTelefonicaFisicamenteResultado> ejecutar({
    required String lineaTelefonicaId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return EliminarLineaTelefonicaFisicamenteMotivoRequerido();

    try {
      return await _repository.eliminarFisicamente(
        lineaTelefonicaId: lineaTelefonicaId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarLineaTelefonicaFisicamenteErrorInesperado(e.toString());
    }
  }
}
