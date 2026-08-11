import '../repositories/categoria_articulo_repository.dart';

/// Resultado de la eliminación física extraordinaria de una
/// [CategoriaArticuloData] (Etapa 11D) — ver el doc comment de
/// `CategoriaArticuloRepositoryImpl.eliminarFisicamente` para las
/// condiciones exactas de elegibilidad.
sealed class EliminarCategoriaArticuloFisicamenteResultado {}

class EliminarCategoriaArticuloFisicamenteExitoso extends EliminarCategoriaArticuloFisicamenteResultado {}

class EliminarCategoriaArticuloFisicamenteNoExiste extends EliminarCategoriaArticuloFisicamenteResultado {}

class EliminarCategoriaArticuloFisicamenteMotivoRequerido extends EliminarCategoriaArticuloFisicamenteResultado {}

/// La Categoría tiene Artículos registrados — no es un simple error de
/// captura, así que la eliminación física se rechaza siempre, sin
/// excepción.
class EliminarCategoriaArticuloFisicamenteTieneDependencias extends EliminarCategoriaArticuloFisicamenteResultado {
  EliminarCategoriaArticuloFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

/// Reservado para la frontera de autorización (facultad Maestro-only,
/// Etapa 11D) — nunca lo produce el propio caso de uso.
class EliminarCategoriaArticuloFisicamenteErrorInesperado extends EliminarCategoriaArticuloFisicamenteResultado {
  EliminarCategoriaArticuloFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Eliminación física extraordinaria de una CategoriaArticulo (Etapa
/// 11D) — la única forma de borrado real de este catálogo, exclusiva
/// del Usuario Maestro (verificado en la fachada de aplicación con
/// `exigirMaestro`, nunca aquí — este caso de uso es puro). `motivo`
/// siempre obligatorio, sin excepción. Toda la validación de
/// dependencias + snapshot + registro de auditoría + `DELETE` ocurre
/// transaccionalmente dentro de
/// `CategoriaArticuloRepositoryImpl.eliminarFisicamente` — este caso de
/// uso solo valida `motivo` y traduce el resultado.
class EliminarCategoriaArticuloFisicamenteUseCase {
  EliminarCategoriaArticuloFisicamenteUseCase(this._repository);

  final CategoriaArticuloRepository _repository;

  Future<EliminarCategoriaArticuloFisicamenteResultado> ejecutar({
    required String categoriaArticuloId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return EliminarCategoriaArticuloFisicamenteMotivoRequerido();

    try {
      return await _repository.eliminarFisicamente(
        categoriaArticuloId: categoriaArticuloId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarCategoriaArticuloFisicamenteErrorInesperado(e.toString());
    }
  }
}
