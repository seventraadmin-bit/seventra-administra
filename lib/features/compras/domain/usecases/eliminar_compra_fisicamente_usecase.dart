import '../repositories/compra_repository.dart';

/// Motivo estructurado de eliminación física de una Compra (Etapa 15,
/// Maestro-only) — mismo criterio que `MotivoCancelacionCompra`: se
/// persiste el nombre estable del enum en
/// `EliminacionFisicaEvento.motivoCodigo`, nunca la etiqueta. `otro` es
/// el único valor que exige `detalle`.
enum MotivoEliminacionFisicaCompra {
  registroDePrueba,
  registroDuplicado,
  errorDeCaptura,
  registroCreadoPorEquivocacion,
  otro,
}

/// Etiqueta traducida de cada [MotivoEliminacionFisicaCompra] — se
/// persiste también en `EliminacionFisicaEvento.motivo` (texto libre,
/// siempre poblado por compatibilidad con el resto de dominios que
/// comparten esa tabla).
extension MotivoEliminacionFisicaCompraLabel on MotivoEliminacionFisicaCompra {
  String get etiqueta => switch (this) {
        MotivoEliminacionFisicaCompra.registroDePrueba => 'Registro de prueba',
        MotivoEliminacionFisicaCompra.registroDuplicado => 'Registro duplicado',
        MotivoEliminacionFisicaCompra.errorDeCaptura => 'Error de captura',
        MotivoEliminacionFisicaCompra.registroCreadoPorEquivocacion => 'Registro creado por equivocación',
        MotivoEliminacionFisicaCompra.otro => 'Otro',
      };
}

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

/// `motivo == MotivoEliminacionFisicaCompra.otro` sin `detalle` capturado.
class EliminarCompraFisicamenteDetalleRequerido extends EliminarCompraFisicamenteResultado {}

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
/// caso de uso es puro). `motivo` siempre obligatorio (enum
/// estructurado, Etapa 15); `otro` exige `detalle`. Toda la validación
/// de dependencias + snapshot + registro de auditoría + `DELETE`
/// (Compra, su Egreso, y las integraciones de Inventario que generó)
/// ocurre transaccionalmente dentro de
/// `CompraRepositoryImpl.eliminarFisicamente`.
class EliminarCompraFisicamenteUseCase {
  EliminarCompraFisicamenteUseCase(this._repository);

  final CompraRepository _repository;

  Future<ResumenEliminacionCompra> obtenerResumen(String compraId) {
    return _repository.obtenerResumenEliminacionFisica(compraId);
  }

  Future<EliminarCompraFisicamenteResultado> ejecutar({
    required String compraId,
    required MotivoEliminacionFisicaCompra motivo,
    String? detalle,
    String? actorUsuarioId,
  }) async {
    final detalleLimpio = detalle?.trim();
    if (motivo == MotivoEliminacionFisicaCompra.otro && (detalleLimpio == null || detalleLimpio.isEmpty)) {
      return EliminarCompraFisicamenteDetalleRequerido();
    }

    try {
      return await _repository.eliminarFisicamente(
        compraId: compraId,
        motivo: motivo.name,
        detalle: detalleLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarCompraFisicamenteErrorInesperado(e.toString());
    }
  }
}
