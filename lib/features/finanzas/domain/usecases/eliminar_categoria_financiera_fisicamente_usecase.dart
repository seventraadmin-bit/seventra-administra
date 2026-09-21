import '../repositories/categoria_financiera_repository.dart';

/// Resumen de solo lectura de si una Categoría financiera es elegible
/// para eliminación física (Etapa 18) — `detalleBloqueo` no nulo
/// significa que un Ingreso y/o Egreso real todavía la referencia
/// (`categoriaFinancieraId`, `onDelete: restrict`); en ese caso la
/// eliminación se rechaza siempre, sin importar motivo, y Archivar
/// sigue disponible como alternativa no destructiva.
class ResumenEliminacionCategoriaFinanciera {
  const ResumenEliminacionCategoriaFinanciera({required this.existe, this.detalleBloqueo});

  final bool existe;
  final String? detalleBloqueo;

  bool get bloqueado => detalleBloqueo != null;
}

sealed class EliminarCategoriaFinancieraFisicamenteResultado {}

class EliminarCategoriaFinancieraFisicamenteExitoso extends EliminarCategoriaFinancieraFisicamenteResultado {}

class EliminarCategoriaFinancieraFisicamenteNoExiste extends EliminarCategoriaFinancieraFisicamenteResultado {}

class EliminarCategoriaFinancieraFisicamenteMotivoRequerido extends EliminarCategoriaFinancieraFisicamenteResultado {}

/// La Categoría tiene Ingresos y/o Egresos registrados que la
/// referencian — se rechaza siempre, sin excepción; `detalle` nombra
/// las cantidades reales, nunca un mensaje genérico.
class EliminarCategoriaFinancieraFisicamenteTieneDependencias extends EliminarCategoriaFinancieraFisicamenteResultado {
  EliminarCategoriaFinancieraFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

/// Reservado para la frontera de autorización (facultad Maestro-only,
/// mismo criterio que el resto de eliminaciones físicas) — nunca lo
/// produce el propio caso de uso.
class EliminarCategoriaFinancieraFisicamenteErrorInesperado extends EliminarCategoriaFinancieraFisicamenteResultado {
  EliminarCategoriaFinancieraFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Eliminación física extraordinaria de una CategoriaFinanciera (Etapa
/// 18) — exclusiva del Usuario Maestro (verificado en la fachada de
/// aplicación con `exigirMaestro`, nunca aquí — este caso de uso es
/// puro). `motivo` siempre obligatorio, sin excepción. Toda la
/// validación de dependencias + snapshot + registro de auditoría +
/// `DELETE` ocurre transaccionalmente dentro de
/// `CategoriaFinancieraRepositoryImpl.eliminarFisicamente`.
class EliminarCategoriaFinancieraFisicamenteUseCase {
  EliminarCategoriaFinancieraFisicamenteUseCase(this._repository);

  final CategoriaFinancieraRepository _repository;

  Future<ResumenEliminacionCategoriaFinanciera> obtenerResumen(String categoriaFinancieraId) {
    return _repository.obtenerResumenEliminacionFisica(categoriaFinancieraId);
  }

  Future<EliminarCategoriaFinancieraFisicamenteResultado> ejecutar({
    required String categoriaFinancieraId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return EliminarCategoriaFinancieraFisicamenteMotivoRequerido();

    try {
      return await _repository.eliminarFisicamente(
        categoriaFinancieraId: categoriaFinancieraId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarCategoriaFinancieraFisicamenteErrorInesperado(e.toString());
    }
  }
}
