import '../repositories/sucursal_repository.dart';

/// Resultado de la eliminación física extraordinaria de una
/// [SucursalData] (Etapa 11D) — ver el doc comment de
/// `SucursalRepositoryImpl.eliminarFisicamente` para las condiciones
/// exactas de elegibilidad.
sealed class EliminarSucursalFisicamenteResultado {}

class EliminarSucursalFisicamenteExitoso extends EliminarSucursalFisicamenteResultado {}

class EliminarSucursalFisicamenteNoExiste extends EliminarSucursalFisicamenteResultado {}

class EliminarSucursalFisicamenteMotivoRequerido extends EliminarSucursalFisicamenteResultado {}

/// La Sucursal tiene Servicios, Ubicaciones, Empleados (o cualquier
/// otra dependencia real descubierta en el grafo de FK) registrados —
/// no es un simple error de captura, así que la eliminación física se
/// rechaza siempre, sin excepción.
class EliminarSucursalFisicamenteTieneDependencias extends EliminarSucursalFisicamenteResultado {
  EliminarSucursalFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

/// Reservado para la frontera de autorización (facultad Maestro-only,
/// Etapa 11D) — nunca lo produce el propio caso de uso.
class EliminarSucursalFisicamenteErrorInesperado extends EliminarSucursalFisicamenteResultado {
  EliminarSucursalFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Eliminación física extraordinaria de una Sucursal (Etapa 11D) — la
/// única forma de borrado real de este dominio, exclusiva del Usuario
/// Maestro (verificado en la fachada de aplicación con
/// `exigirMaestro`, nunca aquí — este caso de uso es puro). `motivo`
/// siempre obligatorio, sin excepción. Toda la validación de
/// dependencias + snapshot + registro de auditoría + `DELETE` ocurre
/// transaccionalmente dentro de
/// `SucursalRepositoryImpl.eliminarFisicamente` — este caso de uso
/// solo valida `motivo` y traduce el resultado.
class EliminarSucursalFisicamenteUseCase {
  EliminarSucursalFisicamenteUseCase(this._repository);

  final SucursalRepository _repository;

  Future<EliminarSucursalFisicamenteResultado> ejecutar({
    required String sucursalId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return EliminarSucursalFisicamenteMotivoRequerido();

    try {
      return await _repository.eliminarFisicamente(
        sucursalId: sucursalId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarSucursalFisicamenteErrorInesperado(e.toString());
    }
  }
}
