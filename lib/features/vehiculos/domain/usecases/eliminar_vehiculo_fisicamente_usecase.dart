import '../repositories/vehiculo_repository.dart';

/// Resultado de la eliminación física extraordinaria de un Vehículo
/// (Etapa 11D) — ver el doc comment de
/// `VehiculoRepositoryImpl.eliminarFisicamente` para las condiciones
/// exactas de elegibilidad.
sealed class EliminarVehiculoFisicamenteResultado {}

class EliminarVehiculoFisicamenteExitoso extends EliminarVehiculoFisicamenteResultado {}

class EliminarVehiculoFisicamenteNoExiste extends EliminarVehiculoFisicamenteResultado {}

class EliminarVehiculoFisicamenteMotivoRequerido extends EliminarVehiculoFisicamenteResultado {}

/// El Vehículo tiene asignaciones, kilometraje, documentos,
/// mantenimiento o fotografía — no es un simple error de captura, así
/// que la eliminación física se rechaza siempre, sin excepción.
class EliminarVehiculoFisicamenteTieneDependencias extends EliminarVehiculoFisicamenteResultado {
  EliminarVehiculoFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

/// Reservado para la frontera de autorización (facultad Maestro-only,
/// Etapa 11D) — nunca lo produce el propio caso de uso.
class EliminarVehiculoFisicamenteErrorInesperado extends EliminarVehiculoFisicamenteResultado {
  EliminarVehiculoFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Eliminación física extraordinaria de un Vehículo (Etapa 11D) — la
/// única forma de borrado real de este dominio, exclusiva del Usuario
/// Maestro (verificado en la fachada de aplicación con `exigirMaestro`,
/// nunca aquí — este caso de uso es puro). `motivo` siempre obligatorio,
/// sin excepción. Toda la validación de dependencias + snapshot +
/// registro de auditoría + `DELETE` ocurre transaccionalmente dentro de
/// `VehiculoRepositoryImpl.eliminarFisicamente` — este caso de uso solo
/// valida `motivo` y traduce el resultado.
class EliminarVehiculoFisicamenteUseCase {
  EliminarVehiculoFisicamenteUseCase(this._repository);

  final VehiculoRepository _repository;

  Future<EliminarVehiculoFisicamenteResultado> ejecutar({
    required String vehiculoId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return EliminarVehiculoFisicamenteMotivoRequerido();

    try {
      return await _repository.eliminarFisicamente(
        vehiculoId: vehiculoId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarVehiculoFisicamenteErrorInesperado(e.toString());
    }
  }
}
