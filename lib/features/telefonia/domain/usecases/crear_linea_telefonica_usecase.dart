import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/result.dart';

import '../repositories/linea_telefonica_repository.dart';

sealed class CrearLineaTelefonicaResultado {}

class CrearLineaTelefonicaExitoso extends CrearLineaTelefonicaResultado {
  CrearLineaTelefonicaExitoso(this.linea);
  final LineaTelefonicaData linea;
}

class CrearLineaTelefonicaNumeroDuplicado extends CrearLineaTelefonicaResultado {}

/// `operador == otro` sin `operadorOtroNombre` — sin eso, "Otro" no
/// sirve para identificar el operador real.
class CrearLineaTelefonicaOperadorOtroNombreRequerido extends CrearLineaTelefonicaResultado {}

class CrearLineaTelefonicaErrorInesperado extends CrearLineaTelefonicaResultado {
  CrearLineaTelefonicaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Da de alta una línea telefónica (Etapa 9A). Solo `operador`/
/// `modalidadSim` son obligatorios además del código (generado) —
/// `numero` queda opcional a propósito (SIM en trámite sin número
/// asignado todavía, mismo criterio que `Vehiculo.placas`).
class CrearLineaTelefonicaUseCase {
  CrearLineaTelefonicaUseCase(this._repository, this._generarCodigo);

  final LineaTelefonicaRepository _repository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<CrearLineaTelefonicaResultado> ejecutar({
    String? numero,
    required String operador,
    String? operadorOtroNombre,
    required String modalidadSim,
    String? iccid,
    DateTime? fechaActivacion,
    String? observaciones,
  }) async {
    if (operador == 'otro' && (operadorOtroNombre == null || operadorOtroNombre.trim().isEmpty)) {
      return CrearLineaTelefonicaOperadorOtroNombreRequerido();
    }

    final numeroNormalizado = numero?.trim().isEmpty ?? true ? null : numero!.trim();
    if (numeroNormalizado != null && await _repository.obtenerPorNumero(numeroNormalizado) != null) {
      return CrearLineaTelefonicaNumeroDuplicado();
    }

    try {
      final codigoResultado = await _generarCodigo.ejecutar('linea_telefonica');
      final String codigo;
      switch (codigoResultado) {
        case Ok<String>(value: final v):
          codigo = v;
        case Err<String>(failure: final f):
          return CrearLineaTelefonicaErrorInesperado(f.message);
      }

      final linea = await _repository.crear(
        codigo: codigo,
        numero: numeroNormalizado,
        operador: operador,
        operadorOtroNombre: operador == 'otro' ? operadorOtroNombre!.trim() : null,
        modalidadSim: modalidadSim,
        iccid: iccid?.trim().isEmpty ?? true ? null : iccid!.trim(),
        fechaActivacion: fechaActivacion,
        observaciones: observaciones?.trim().isEmpty ?? true ? null : observaciones!.trim(),
      );
      return CrearLineaTelefonicaExitoso(linea);
    } catch (e) {
      return CrearLineaTelefonicaErrorInesperado(e.toString());
    }
  }
}
