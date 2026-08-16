import '../repositories/pago_repository.dart';

/// Resumen de solo lectura de si un Pago es elegible para eliminación
/// física (Etapa 15) — insumo del mensaje de confirmación que la UI
/// muestra antes de pedir el motivo. `detalleBloqueo` no nulo
/// significa: el Pago sigue activo (debe cancelarse primero, lo que ya
/// cancela en cascada todas sus `AplicacionPago` activas), o tiene un
/// `ComplementoPago` registrado — un CFDI ya timbrado externamente
/// ante el SAT, constancia de una obligación fiscal real que nunca se
/// borra, sin importar su estatus. Un Pago cancelado sin Complemento
/// SÍ es elegible (caso real: limpiar un Pago de prueba).
class ResumenEliminacionPago {
  const ResumenEliminacionPago({required this.existe, this.detalleBloqueo});

  final bool existe;
  final String? detalleBloqueo;

  bool get bloqueado => detalleBloqueo != null;
}

sealed class EliminarPagoFisicamenteResultado {}

class EliminarPagoFisicamenteExitoso extends EliminarPagoFisicamenteResultado {}

class EliminarPagoFisicamenteNoExiste extends EliminarPagoFisicamenteResultado {}

class EliminarPagoFisicamenteMotivoRequerido extends EliminarPagoFisicamenteResultado {}

/// El Pago sigue activo o tiene un `ComplementoPago` real registrado —
/// `detalle` siempre nombra la razón exacta, nunca un mensaje genérico.
class EliminarPagoFisicamenteTieneDependencias extends EliminarPagoFisicamenteResultado {
  EliminarPagoFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

class EliminarPagoFisicamenteErrorInesperado extends EliminarPagoFisicamenteResultado {
  EliminarPagoFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Eliminación física extraordinaria de un `Pago` (Etapa 15) —
/// exclusiva del Usuario Maestro (`exigirMaestro`, nunca aquí — este
/// caso de uso es puro). `motivo` siempre obligatorio. Un Pago activo
/// nunca se borra directo: debe cancelarse primero (lo que ya cancela
/// en cascada sus aplicaciones y su Ingreso automático) — solo un Pago
/// ya cancelado, sin Complemento de pago real, es elegible. Toda la
/// validación + snapshot + registro de auditoría + `DELETE` (Pago, sus
/// `AplicacionPago` canceladas, y su `Ingreso` cancelado) ocurre
/// transaccionalmente dentro de `PagoRepositoryImpl.eliminarFisicamente`.
class EliminarPagoFisicamenteUseCase {
  EliminarPagoFisicamenteUseCase(this._repository);

  final PagoRepository _repository;

  Future<ResumenEliminacionPago> obtenerResumen(String pagoId) {
    return _repository.obtenerResumenEliminacionFisica(pagoId);
  }

  Future<EliminarPagoFisicamenteResultado> ejecutar({
    required String pagoId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return EliminarPagoFisicamenteMotivoRequerido();

    try {
      return await _repository.eliminarFisicamente(
        pagoId: pagoId,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarPagoFisicamenteErrorInesperado(e.toString());
    }
  }
}
