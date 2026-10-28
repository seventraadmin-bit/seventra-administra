import '../repositories/descuento_programado_repository.dart';

/// Eliminación física extraordinaria de un descuento programado
/// (préstamo/botas) — pedido explícito: dar al Maestro una forma de
/// borrar por pruebas un descuento que se canceló por error, sin dejar
/// el registro visible para siempre. Exclusiva del Usuario Maestro
/// (`exigirMaestro`, nunca aquí; este caso de uso es puro) y exclusiva
/// de un descuento ya `cancelado` — mismo criterio que el resto del
/// proyecto: la validación de negocio vive en el caso de uso, la
/// escritura cruda en `DescuentoProgramadoRepositoryImpl.
/// eliminarFisicamente`.
class EliminarDescuentoProgramadoFisicamenteUseCase {
  EliminarDescuentoProgramadoFisicamenteUseCase(this._repository);

  final DescuentoProgramadoRepository _repository;

  Future<ResumenEliminacionDescuentoProgramado> obtenerResumen(
    String descuentoProgramadoId,
  ) {
    return _repository.obtenerResumenEliminacionFisica(descuentoProgramadoId);
  }

  Future<EliminarDescuentoProgramadoFisicamenteResultado> ejecutar({
    required String descuentoProgramadoId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final descuento = await _repository.obtenerPorId(descuentoProgramadoId);
    if (descuento == null) {
      return EliminarDescuentoProgramadoFisicamenteNoExiste();
    }
    if (descuento.estatus != 'cancelado') {
      return EliminarDescuentoProgramadoFisicamenteNoPermitido();
    }

    try {
      return await _repository.eliminarFisicamente(
        descuentoProgramadoId: descuentoProgramadoId,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarDescuentoProgramadoFisicamenteErrorInesperado(
        e.toString(),
      );
    }
  }
}
