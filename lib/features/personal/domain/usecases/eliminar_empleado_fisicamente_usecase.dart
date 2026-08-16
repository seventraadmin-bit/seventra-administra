import '../repositories/empleado_repository.dart';

/// Resumen de solo lectura de si un Empleado es elegible para
/// eliminación física (Etapa 15) — insumo del mensaje de confirmación
/// que la UI muestra antes de pedir el motivo. `detalleBloqueo` no nulo
/// significa que existe historia real (Nómina generada, Asignación a
/// Servicio, resguardo/reclamo de Inventario, Vehículo o Línea
/// telefónica asignados) — nunca la Ficha técnica, que se limpia junto
/// con el Empleado (Resolución explícita de Marlon: los expedientes de
/// prueba de esta etapa ya generaron fichas técnicas y eso no debe
/// impedir limpiarlos).
class ResumenEliminacionEmpleado {
  const ResumenEliminacionEmpleado({
    required this.existe,
    this.cantidadFichasTecnicas = 0,
    this.cantidadDocumentos = 0,
    this.detalleBloqueo,
  });

  final bool existe;
  final int cantidadFichasTecnicas;
  final int cantidadDocumentos;
  final String? detalleBloqueo;

  bool get bloqueado => detalleBloqueo != null;
}

sealed class EliminarEmpleadoFisicamenteResultado {}

class EliminarEmpleadoFisicamenteExitoso extends EliminarEmpleadoFisicamenteResultado {
  EliminarEmpleadoFisicamenteExitoso({this.archivosNoEliminadosFisicamente = const []});

  /// Nombres (no rutas completas) de los adjuntos cuya fila de BD sí se
  /// borró pero cuyo archivo físico no se pudo eliminar (permisos,
  /// archivo en uso, etc.) — el Empleado igual queda eliminado (la BD
  /// es la fuente de verdad), pero esto nunca se oculta.
  final List<String> archivosNoEliminadosFisicamente;
}

class EliminarEmpleadoFisicamenteNoExiste extends EliminarEmpleadoFisicamenteResultado {}

class EliminarEmpleadoFisicamenteMotivoRequerido extends EliminarEmpleadoFisicamenteResultado {}

/// El Empleado tiene historia real que no es seguro revertir — `detalle`
/// siempre nombra la dependencia real, nunca un mensaje genérico.
class EliminarEmpleadoFisicamenteTieneDependencias extends EliminarEmpleadoFisicamenteResultado {
  EliminarEmpleadoFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

class EliminarEmpleadoFisicamenteErrorInesperado extends EliminarEmpleadoFisicamenteResultado {
  EliminarEmpleadoFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Eliminación física extraordinaria de un `Empleado` (Etapa 15) —
/// exclusiva del Usuario Maestro (`exigirMaestro`, nunca aquí — este
/// caso de uso es puro). `motivo` siempre obligatorio. Toda la
/// validación de dependencias + snapshot + registro de auditoría +
/// `DELETE` (Empleado, su domicilio, sus Fichas técnicas y sus
/// documentos/fotografía) ocurre transaccionalmente dentro de
/// `EmpleadoRepositoryImpl.eliminarFisicamente`.
class EliminarEmpleadoFisicamenteUseCase {
  EliminarEmpleadoFisicamenteUseCase(this._repository);

  final EmpleadoRepository _repository;

  Future<ResumenEliminacionEmpleado> obtenerResumen(String empleadoId) {
    return _repository.obtenerResumenEliminacionFisica(empleadoId);
  }

  Future<EliminarEmpleadoFisicamenteResultado> ejecutar({
    required String empleadoId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return EliminarEmpleadoFisicamenteMotivoRequerido();

    try {
      return await _repository.eliminarFisicamente(
        empleadoId: empleadoId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarEmpleadoFisicamenteErrorInesperado(e.toString());
    }
  }
}
