import '../repositories/compra_repository.dart';

/// Resumen de solo lectura de si una Compra es elegible para
/// eliminación física (Etapa 15) — insumo del mensaje de confirmación
/// que la UI muestra antes de pedir el motivo. `detalleBloqueo` no nulo
/// significa que existe historia real posterior a la propia Compra
/// (una unidad asignada, vinculada a una línea telefónica, o con
/// movimientos adicionales; o un artículo por cantidad con
/// asignaciones registradas) — nunca el propio Egreso generado, que se
/// elimina junto con la Compra como parte del mismo agregado.
class ResumenEliminacionCompra {
  const ResumenEliminacionCompra({required this.existe, this.detalleBloqueo});

  final bool existe;
  final String? detalleBloqueo;

  bool get bloqueado => detalleBloqueo != null;
}

sealed class EliminarCompraFisicamenteResultado {}

class EliminarCompraFisicamenteExitoso extends EliminarCompraFisicamenteResultado {}

class EliminarCompraFisicamenteNoExiste extends EliminarCompraFisicamenteResultado {}

class EliminarCompraFisicamenteMotivoRequerido extends EliminarCompraFisicamenteResultado {}

/// La Compra generó historia real posterior que no es seguro revertir
/// (una unidad ya asignada/vinculada a una línea telefónica, o un
/// artículo por cantidad con asignaciones registradas) — `detalle`
/// siempre nombra la dependencia real, nunca un mensaje genérico.
class EliminarCompraFisicamenteTieneDependencias extends EliminarCompraFisicamenteResultado {
  EliminarCompraFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

class EliminarCompraFisicamenteErrorInesperado extends EliminarCompraFisicamenteResultado {
  EliminarCompraFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Eliminación física extraordinaria de una `Compra` (Etapa 15) —
/// exclusiva del Usuario Maestro (`exigirMaestro`, nunca aquí — este
/// caso de uso es puro). `motivo` siempre obligatorio. Toda la
/// validación de dependencias + snapshot + registro de auditoría +
/// `DELETE` (Compra, su Egreso, y las integraciones de Inventario que
/// generó) ocurre transaccionalmente dentro de
/// `CompraRepositoryImpl.eliminarFisicamente`.
class EliminarCompraFisicamenteUseCase {
  EliminarCompraFisicamenteUseCase(this._repository);

  final CompraRepository _repository;

  Future<ResumenEliminacionCompra> obtenerResumen(String compraId) {
    return _repository.obtenerResumenEliminacionFisica(compraId);
  }

  Future<EliminarCompraFisicamenteResultado> ejecutar({
    required String compraId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return EliminarCompraFisicamenteMotivoRequerido();

    try {
      return await _repository.eliminarFisicamente(
        compraId: compraId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarCompraFisicamenteErrorInesperado(e.toString());
    }
  }
}
