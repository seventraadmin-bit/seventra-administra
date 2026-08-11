import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/linea_telefonica_repository.dart';

sealed class CorregirLineaTelefonicaResultado {}

class CorregirLineaTelefonicaExitoso extends CorregirLineaTelefonicaResultado {
  CorregirLineaTelefonicaExitoso(this.linea);
  final LineaTelefonicaData linea;
}

class CorregirLineaTelefonicaNoExiste extends CorregirLineaTelefonicaResultado {}

class CorregirLineaTelefonicaNumeroDuplicado extends CorregirLineaTelefonicaResultado {}

class CorregirLineaTelefonicaOperadorOtroNombreRequerido extends CorregirLineaTelefonicaResultado {}

class CorregirLineaTelefonicaErrorInesperado extends CorregirLineaTelefonicaResultado {
  CorregirLineaTelefonicaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige metadatos de una línea telefónica — nunca `codigo` (generado,
/// fijo desde la creación, mismo criterio que `Vehiculo.codigo`).
class CorregirLineaTelefonicaUseCase {
  CorregirLineaTelefonicaUseCase(this._repository);

  final LineaTelefonicaRepository _repository;

  Future<CorregirLineaTelefonicaResultado> ejecutar({
    required String lineaTelefonicaId,
    String? numero,
    String? operador,
    String? operadorOtroNombre,
    String? modalidadSim,
    String? iccid,
    DateTime? fechaActivacion,
    String? observaciones,
    bool limpiarNumero = false,
    bool limpiarOperadorOtroNombre = false,
    bool limpiarIccid = false,
    bool limpiarFechaActivacion = false,
    bool limpiarObservaciones = false,
  }) async {
    final linea = await _repository.obtenerPorId(lineaTelefonicaId);
    if (linea == null) return CorregirLineaTelefonicaNoExiste();

    final operadorFinal = operador ?? linea.operador;
    if (operadorFinal == 'otro') {
      final nombreFinal = operadorOtroNombre ?? (limpiarOperadorOtroNombre ? null : linea.operadorOtroNombre);
      if (nombreFinal == null || nombreFinal.trim().isEmpty) {
        return CorregirLineaTelefonicaOperadorOtroNombreRequerido();
      }
    }

    final numeroNormalizado = numero?.trim().isEmpty ?? true ? null : numero!.trim();
    if (numeroNormalizado != null) {
      final existente = await _repository.obtenerPorNumero(numeroNormalizado);
      if (existente != null && existente.id != lineaTelefonicaId) return CorregirLineaTelefonicaNumeroDuplicado();
    }

    try {
      final actualizada = await _repository.corregir(
        lineaTelefonicaId: lineaTelefonicaId,
        numero: numeroNormalizado,
        operador: operador,
        operadorOtroNombre: operadorFinal == 'otro' ? operadorOtroNombre?.trim() : null,
        modalidadSim: modalidadSim,
        iccid: iccid,
        fechaActivacion: fechaActivacion,
        observaciones: observaciones,
        limpiarNumero: limpiarNumero,
        limpiarOperadorOtroNombre: operadorFinal != 'otro' || limpiarOperadorOtroNombre,
        limpiarIccid: limpiarIccid,
        limpiarFechaActivacion: limpiarFechaActivacion,
        limpiarObservaciones: limpiarObservaciones,
      );
      return CorregirLineaTelefonicaExitoso(actualizada);
    } catch (e) {
      return CorregirLineaTelefonicaErrorInesperado(e.toString());
    }
  }
}
