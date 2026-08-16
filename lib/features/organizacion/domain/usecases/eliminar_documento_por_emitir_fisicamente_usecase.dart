import '../repositories/documento_por_emitir_repository.dart';

/// Resumen de solo lectura de lo que la eliminación física haría con
/// un `DocumentoPorEmitir` (Etapa 15) — insumo del mensaje de
/// confirmación dinámico que la UI muestra antes de pedir el motivo:
/// "Este documento tiene una Cuenta por Cobrar sin pagos y 2 archivos
/// adjuntos. Se eliminarán junto con el documento." Nunca muta nada.
class ResumenEliminacionDocumentoPorEmitir {
  const ResumenEliminacionDocumentoPorEmitir({
    required this.existe,
    required this.tieneCuentaPorCobrar,
    required this.cantidadAdjuntos,
    required this.bloqueadoPorPago,
    this.detalleBloqueo,
  });

  final bool existe;
  final bool tieneCuentaPorCobrar;
  final int cantidadAdjuntos;

  /// `true` si la Cuenta por cobrar tiene al menos una `AplicacionPago`
  /// real (aplicada o cancelada — ambas implican que hubo un `Pago`) —
  /// el único bloqueador real. Si es `true`, la eliminación siempre se
  /// rechaza, sin importar motivo.
  final bool bloqueadoPorPago;

  /// Mensaje específico de qué dependencia financiera debe resolverse
  /// primero — solo presente cuando `bloqueadoPorPago == true`.
  final String? detalleBloqueo;
}

/// Resultado de la eliminación física extraordinaria de un
/// `DocumentoPorEmitir` (Etapa 15) — ver el doc comment de
/// `DocumentoPorEmitirRepositoryImpl.eliminarFisicamente` para las
/// condiciones exactas de elegibilidad.
sealed class EliminarDocumentoPorEmitirFisicamenteResultado {}

class EliminarDocumentoPorEmitirFisicamenteExitoso extends EliminarDocumentoPorEmitirFisicamenteResultado {
  EliminarDocumentoPorEmitirFisicamenteExitoso({this.archivosNoEliminadosFisicamente = const []});

  /// Nombres (no rutas completas — nunca se expone la ruta física en
  /// disco a la UI) de los adjuntos cuya fila de BD sí se borró pero
  /// cuyo archivo físico no se pudo eliminar (permisos, archivo en uso,
  /// etc.) — el documento igual queda eliminado (la BD es la fuente de
  /// verdad), pero esto nunca se oculta: la UI debe mostrarlo como
  /// advertencia explícita, nunca como éxito silencioso e incompleto.
  final List<String> archivosNoEliminadosFisicamente;
}

class EliminarDocumentoPorEmitirFisicamenteNoExiste extends EliminarDocumentoPorEmitirFisicamenteResultado {}

class EliminarDocumentoPorEmitirFisicamenteMotivoRequerido extends EliminarDocumentoPorEmitirFisicamenteResultado {}

/// Único bloqueador real (Etapa 15, ampliación explícita de Marlon): la
/// Cuenta por cobrar del documento tiene al menos una `AplicacionPago`
/// real — dinero real ya aplicado a otros registros. El estatus del
/// documento y la sola existencia de adjuntos/Cuenta por cobrar SIN
/// pagos aplicados YA NO bloquean por sí solos — se limpian
/// explícitamente como parte de la misma eliminación.
class EliminarDocumentoPorEmitirFisicamenteTieneDependencias extends EliminarDocumentoPorEmitirFisicamenteResultado {
  EliminarDocumentoPorEmitirFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

/// Reservado para la frontera de autorización (facultad Maestro-only,
/// Etapa 11D) — nunca lo produce el propio caso de uso.
class EliminarDocumentoPorEmitirFisicamenteErrorInesperado extends EliminarDocumentoPorEmitirFisicamenteResultado {
  EliminarDocumentoPorEmitirFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Eliminación física extraordinaria de un `DocumentoPorEmitir` (Etapa
/// 15) — exclusiva del Usuario Maestro (`exigirMaestro`, nunca aquí —
/// este caso de uso es puro). `motivo` siempre obligatorio. Toda la
/// validación de dependencias + limpieza explícita + snapshot +
/// registro de auditoría + `DELETE` ocurre transaccionalmente dentro de
/// `DocumentoPorEmitirRepositoryImpl.eliminarFisicamente`; los archivos
/// físicos se borran después del commit (ver el doc comment de ese
/// método para el porqué de ese orden).
class EliminarDocumentoPorEmitirFisicamenteUseCase {
  EliminarDocumentoPorEmitirFisicamenteUseCase(this._repository);

  final DocumentoPorEmitirRepository _repository;

  Future<ResumenEliminacionDocumentoPorEmitir> obtenerResumen(String documentoPorEmitirId) {
    return _repository.obtenerResumenEliminacionFisica(documentoPorEmitirId);
  }

  Future<EliminarDocumentoPorEmitirFisicamenteResultado> ejecutar({
    required String documentoPorEmitirId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return EliminarDocumentoPorEmitirFisicamenteMotivoRequerido();

    try {
      return await _repository.eliminarFisicamente(
        documentoPorEmitirId: documentoPorEmitirId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarDocumentoPorEmitirFisicamenteErrorInesperado(e.toString());
    }
  }
}
