import '../repositories/egreso_repository.dart';

/// Resumen de solo lectura de si un Egreso es elegible para
/// eliminación física (Etapa 15; ampliado en la etapa "Ingresos y
/// Egresos") — insumo del mensaje de confirmación que la UI muestra
/// antes de pedir el motivo. `detalleBloqueo` no nulo significa que
/// existe una dependencia real (`Compra`/`PagoNomina`/`TiempoExtra`/
/// `TiempoExtraCostoAdicional`/`MovimientoDeuda` que lo generaron
/// automáticamente) y la eliminación se rechaza siempre, sin importar
/// motivo — nunca se rompe la trazabilidad del origen. Un Egreso
/// `cancelado` sin ningún origen automático SÍ es elegible (caso real:
/// limpiar una captura de prueba).
class ResumenEliminacionEgreso {
  const ResumenEliminacionEgreso({required this.existe, this.detalleBloqueo});

  final bool existe;
  final String? detalleBloqueo;

  bool get bloqueado => detalleBloqueo != null;
}

sealed class EliminarEgresoFisicamenteResultado {}

class EliminarEgresoFisicamenteExitoso extends EliminarEgresoFisicamenteResultado {}

class EliminarEgresoFisicamenteNoExiste extends EliminarEgresoFisicamenteResultado {}

class EliminarEgresoFisicamenteMotivoRequerido extends EliminarEgresoFisicamenteResultado {}

/// Único bloqueo real (Etapa 15): el Egreso fue generado
/// automáticamente por una `Compra` o un `PagoNomina` (`egresoId` de
/// cualquiera de las dos apunta a este Egreso) — eliminarlo aislado
/// dejaría a su origen apuntando a un registro inexistente. `detalle`
/// siempre nombra el folio real del origen, nunca un mensaje genérico.
class EliminarEgresoFisicamenteTieneDependencias extends EliminarEgresoFisicamenteResultado {
  EliminarEgresoFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

class EliminarEgresoFisicamenteErrorInesperado extends EliminarEgresoFisicamenteResultado {
  EliminarEgresoFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Eliminación física extraordinaria de un `Egreso` (Etapa 15) —
/// exclusiva del Usuario Maestro (`exigirMaestro`, nunca aquí — este
/// caso de uso es puro). `motivo` siempre obligatorio. Toda la
/// validación de dependencias + snapshot + registro de auditoría +
/// `DELETE` ocurre transaccionalmente dentro de
/// `EgresoRepositoryImpl.eliminarFisicamente`.
class EliminarEgresoFisicamenteUseCase {
  EliminarEgresoFisicamenteUseCase(this._repository);

  final EgresoRepository _repository;

  Future<ResumenEliminacionEgreso> obtenerResumen(String egresoId) {
    return _repository.obtenerResumenEliminacionFisica(egresoId);
  }

  Future<EliminarEgresoFisicamenteResultado> ejecutar({
    required String egresoId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return EliminarEgresoFisicamenteMotivoRequerido();

    try {
      return await _repository.eliminarFisicamente(
        egresoId: egresoId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarEgresoFisicamenteErrorInesperado(e.toString());
    }
  }
}
