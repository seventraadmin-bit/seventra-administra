import '../repositories/tiempo_extra_repository.dart';

/// Resumen de solo lectura para el mensaje de confirmación de
/// "Eliminar físicamente" — mismo criterio que `ResumenEliminacionCompra`.
class ResumenEliminacionTiempoExtra {
  const ResumenEliminacionTiempoExtra({required this.existe, this.detalleBloqueo});
  final bool existe;
  final String? detalleBloqueo;
  bool get bloqueado => detalleBloqueo != null;
}

sealed class EliminarTiempoExtraFisicamenteResultado {}

class EliminarTiempoExtraFisicamenteExitoso extends EliminarTiempoExtraFisicamenteResultado {}

class EliminarTiempoExtraFisicamenteNoExiste extends EliminarTiempoExtraFisicamenteResultado {}

class EliminarTiempoExtraFisicamenteTieneDependencias extends EliminarTiempoExtraFisicamenteResultado {
  EliminarTiempoExtraFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

class EliminarTiempoExtraFisicamenteErrorInesperado extends EliminarTiempoExtraFisicamenteResultado {
  EliminarTiempoExtraFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

enum MotivoEliminacionFisicaTiempoExtra {
  registroDePrueba,
  registroDuplicado,
  errorDeCaptura,
  registroCreadoPorEquivocacion,
  otro,
}

/// Etiqueta traducida de cada [MotivoEliminacionFisicaTiempoExtra] — se
/// persiste también en `EliminacionFisicaEvento.motivo`, mismo criterio
/// que `MotivoEliminacionFisicaCompraLabel`.
extension MotivoEliminacionFisicaTiempoExtraLabel on MotivoEliminacionFisicaTiempoExtra {
  String get etiqueta => switch (this) {
        MotivoEliminacionFisicaTiempoExtra.registroDePrueba => 'Registro de prueba',
        MotivoEliminacionFisicaTiempoExtra.registroDuplicado => 'Registro duplicado',
        MotivoEliminacionFisicaTiempoExtra.errorDeCaptura => 'Error de captura',
        MotivoEliminacionFisicaTiempoExtra.registroCreadoPorEquivocacion => 'Registro creado por equivocación',
        MotivoEliminacionFisicaTiempoExtra.otro => 'Otro',
      };
}

class EliminarTiempoExtraFisicamenteDetalleRequerido extends EliminarTiempoExtraFisicamenteResultado {}

/// Eliminación física extraordinaria de un `TiempoExtra` (Etapa
/// "corrección real de Tiempo Extra") — exclusiva del Usuario Maestro
/// (`exigirMaestro`, nunca aquí — este caso de uso es puro). Solo
/// elegible si ya está `cancelado` (validado en
/// `TiempoExtraRepositoryImpl.obtenerResumenEliminacionFisica`, nunca
/// aquí) — su efecto financiero neto ya es cero. Toda la validación de
/// dependencias + snapshot + registro de auditoría + `DELETE` ocurre
/// transaccionalmente dentro de `TiempoExtraRepositoryImpl.eliminarFisicamente`.
class EliminarTiempoExtraFisicamenteUseCase {
  EliminarTiempoExtraFisicamenteUseCase(this._repository);

  final TiempoExtraRepository _repository;

  Future<ResumenEliminacionTiempoExtra> obtenerResumen(String tiempoExtraId) {
    return _repository.obtenerResumenEliminacionFisica(tiempoExtraId);
  }

  Future<EliminarTiempoExtraFisicamenteResultado> ejecutar({
    required String tiempoExtraId,
    required MotivoEliminacionFisicaTiempoExtra motivo,
    String? detalle,
    String? actorUsuarioId,
  }) async {
    final detalleLimpio = detalle?.trim();
    if (motivo == MotivoEliminacionFisicaTiempoExtra.otro && (detalleLimpio == null || detalleLimpio.isEmpty)) {
      return EliminarTiempoExtraFisicamenteDetalleRequerido();
    }

    try {
      return await _repository.eliminarFisicamente(
        tiempoExtraId: tiempoExtraId,
        motivo: motivo.name,
        detalle: detalleLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarTiempoExtraFisicamenteErrorInesperado(e.toString());
    }
  }
}
