import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/nomina_repository.dart';

sealed class ActualizarMovimientosNominaResultado {}

class ActualizarMovimientosNominaExitoso extends ActualizarMovimientosNominaResultado {
  ActualizarMovimientosNominaExitoso(this.renglon);
  final NominaEmpleadoData renglon;
}

class ActualizarMovimientosNominaNoExiste extends ActualizarMovimientosNominaResultado {}

/// La Nómina ya no está en Borrador — congelada, ver el doc comment de
/// `Nomina`.
class ActualizarMovimientosNominaNominaCerrada extends ActualizarMovimientosNominaResultado {}

class ActualizarMovimientosNominaValorInvalido extends ActualizarMovimientosNominaResultado {}

/// Captura los movimientos manuales de un renglón de Nómina (Etapa 6C)
/// — préstamo, tiempo extra, bono, faltas, otros descuentos,
/// observaciones. Solo permitido mientras la Nómina esté en Borrador.
///
/// `bono` marca `bonoModificadoManualmente` en cuanto se toca — evita
/// que `ActualizarNominaDesdePersonalUseCase` lo vuelva a proponer
/// automáticamente después (Resolución explícita de Marlon).
class ActualizarMovimientosNominaUseCase {
  ActualizarMovimientosNominaUseCase(this._nominaRepository);

  final NominaRepository _nominaRepository;

  Future<ActualizarMovimientosNominaResultado> ejecutar({
    required String nominaEmpleadoId,
    int? prestamo,
    int? tiempoExtra,
    int? bono,
    int? faltas,
    int? otrosDescuentos,
    String? observaciones,
    bool limpiarObservaciones = false,
  }) async {
    final renglon = await _nominaRepository.obtenerEmpleado(nominaEmpleadoId);
    if (renglon == null) return ActualizarMovimientosNominaNoExiste();

    final nomina = await _nominaRepository.obtenerPorId(renglon.nominaId);
    if (nomina == null || nomina.estatus != 'borrador') return ActualizarMovimientosNominaNominaCerrada();

    final nuevoPrestamo = prestamo ?? renglon.prestamo;
    final nuevoTiempoExtra = tiempoExtra ?? renglon.tiempoExtra;
    final nuevoBono = bono ?? renglon.bono;
    final nuevoFaltas = faltas ?? renglon.faltas;
    final nuevoOtrosDescuentos = otrosDescuentos ?? renglon.otrosDescuentos;
    final nuevasObservaciones = limpiarObservaciones ? null : (observaciones ?? renglon.observaciones);

    if (nuevoPrestamo < 0 || nuevoTiempoExtra < 0 || nuevoBono < 0 || nuevoFaltas < 0 || nuevoOtrosDescuentos < 0) {
      return ActualizarMovimientosNominaValorInvalido();
    }

    final bonoModificadoManualmente = bono != null ? true : renglon.bonoModificadoManualmente;

    final actualizado = await _nominaRepository.actualizarMovimientos(
      nominaEmpleadoId: nominaEmpleadoId,
      prestamo: nuevoPrestamo,
      tiempoExtra: nuevoTiempoExtra,
      bono: nuevoBono,
      bonoModificadoManualmente: bonoModificadoManualmente,
      faltas: nuevoFaltas,
      otrosDescuentos: nuevoOtrosDescuentos,
      observaciones: nuevasObservaciones,
    );
    await _nominaRepository.registrarEvento(
      nominaId: renglon.nominaId,
      nominaEmpleadoId: nominaEmpleadoId,
      tipoEvento: 'movimientoModificado',
    );
    return ActualizarMovimientosNominaExitoso(actualizado);
  }
}
