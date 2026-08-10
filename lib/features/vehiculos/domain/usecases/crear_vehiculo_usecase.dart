import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/result.dart';

import '../repositories/vehiculo_repository.dart';

sealed class CrearVehiculoResultado {}

class CrearVehiculoExitoso extends CrearVehiculoResultado {
  CrearVehiculoExitoso(this.vehiculo);
  final VehiculoData vehiculo;
}

class CrearVehiculoMarcaRequerida extends CrearVehiculoResultado {}

class CrearVehiculoModeloRequerido extends CrearVehiculoResultado {}

class CrearVehiculoAnioInvalido extends CrearVehiculoResultado {}

class CrearVehiculoCostoInvalido extends CrearVehiculoResultado {}

class CrearVehiculoPlacasDuplicadas extends CrearVehiculoResultado {}

class CrearVehiculoVinDuplicado extends CrearVehiculoResultado {}

class CrearVehiculoErrorInesperado extends CrearVehiculoResultado {
  CrearVehiculoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Da de alta un Vehículo en la flotilla (Etapa 8A). Solo `marca`/
/// `modelo` son obligatorios además del código (generado) y el tipo —
/// el resto queda opcional a propósito (Resolución explícita de
/// Marlon: "no obligar a capturar campos que no siempre conozco").
class CrearVehiculoUseCase {
  CrearVehiculoUseCase(this._repository, this._generarCodigo);

  final VehiculoRepository _repository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<CrearVehiculoResultado> ejecutar({
    required String marca,
    required String modelo,
    int? anio,
    String? color,
    String? placas,
    String? vin,
    String? numeroMotor,
    required String tipoVehiculo,
    DateTime? fechaAdquisicion,
    int? costoAdquisicion,
    String? observaciones,
  }) async {
    if (marca.trim().isEmpty) return CrearVehiculoMarcaRequerida();
    if (modelo.trim().isEmpty) return CrearVehiculoModeloRequerido();
    final anioActual = DateTime.now().year;
    if (anio != null && (anio < 1980 || anio > anioActual + 1)) return CrearVehiculoAnioInvalido();
    if (costoAdquisicion != null && costoAdquisicion < 0) return CrearVehiculoCostoInvalido();

    final placasNormalizadas = placas?.trim().isEmpty ?? true ? null : placas!.trim().toUpperCase();
    final vinNormalizado = vin?.trim().isEmpty ?? true ? null : vin!.trim().toUpperCase();

    if (placasNormalizadas != null && await _repository.obtenerPorPlacas(placasNormalizadas) != null) {
      return CrearVehiculoPlacasDuplicadas();
    }
    if (vinNormalizado != null && await _repository.obtenerPorVin(vinNormalizado) != null) {
      return CrearVehiculoVinDuplicado();
    }

    try {
      final codigoResultado = await _generarCodigo.ejecutar('vehiculo');
      final String codigo;
      switch (codigoResultado) {
        case Ok<String>(value: final v):
          codigo = v;
        case Err<String>(failure: final f):
          return CrearVehiculoErrorInesperado(f.message);
      }

      final vehiculo = await _repository.crear(
        codigo: codigo,
        marca: marca.trim(),
        modelo: modelo.trim(),
        anio: anio,
        color: color?.trim().isEmpty ?? true ? null : color!.trim(),
        placas: placasNormalizadas,
        vin: vinNormalizado,
        numeroMotor: numeroMotor?.trim().isEmpty ?? true ? null : numeroMotor!.trim(),
        tipoVehiculo: tipoVehiculo,
        fechaAdquisicion: fechaAdquisicion,
        costoAdquisicion: costoAdquisicion,
        observaciones: observaciones?.trim().isEmpty ?? true ? null : observaciones!.trim(),
      );
      return CrearVehiculoExitoso(vehiculo);
    } catch (e) {
      return CrearVehiculoErrorInesperado(e.toString());
    }
  }
}
