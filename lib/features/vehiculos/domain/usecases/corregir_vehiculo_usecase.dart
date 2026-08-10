import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/vehiculo_repository.dart';

sealed class CorregirVehiculoResultado {}

class CorregirVehiculoExitoso extends CorregirVehiculoResultado {
  CorregirVehiculoExitoso(this.vehiculo);
  final VehiculoData vehiculo;
}

class CorregirVehiculoNoExiste extends CorregirVehiculoResultado {}

class CorregirVehiculoAnioInvalido extends CorregirVehiculoResultado {}

class CorregirVehiculoCostoInvalido extends CorregirVehiculoResultado {}

class CorregirVehiculoPlacasDuplicadas extends CorregirVehiculoResultado {}

class CorregirVehiculoVinDuplicado extends CorregirVehiculoResultado {}

class CorregirVehiculoErrorInesperado extends CorregirVehiculoResultado {
  CorregirVehiculoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige metadatos de un Vehículo — nunca `codigo` (generado, fijo
/// desde la creación, mismo criterio que `Articulo.folio`).
class CorregirVehiculoUseCase {
  CorregirVehiculoUseCase(this._repository);

  final VehiculoRepository _repository;

  Future<CorregirVehiculoResultado> ejecutar({
    required String vehiculoId,
    String? marca,
    String? modelo,
    int? anio,
    String? color,
    String? placas,
    String? vin,
    String? numeroMotor,
    String? tipoVehiculo,
    DateTime? fechaAdquisicion,
    int? costoAdquisicion,
    String? observaciones,
    bool limpiarAnio = false,
    bool limpiarColor = false,
    bool limpiarPlacas = false,
    bool limpiarVin = false,
    bool limpiarNumeroMotor = false,
    bool limpiarFechaAdquisicion = false,
    bool limpiarCostoAdquisicion = false,
    bool limpiarObservaciones = false,
  }) async {
    final vehiculo = await _repository.obtenerPorId(vehiculoId);
    if (vehiculo == null) return CorregirVehiculoNoExiste();

    final anioActual = DateTime.now().year;
    if (anio != null && (anio < 1980 || anio > anioActual + 1)) return CorregirVehiculoAnioInvalido();
    if (costoAdquisicion != null && costoAdquisicion < 0) return CorregirVehiculoCostoInvalido();

    final placasNormalizadas = placas?.trim().isEmpty ?? true ? null : placas!.trim().toUpperCase();
    final vinNormalizado = vin?.trim().isEmpty ?? true ? null : vin!.trim().toUpperCase();

    if (placasNormalizadas != null) {
      final existente = await _repository.obtenerPorPlacas(placasNormalizadas);
      if (existente != null && existente.id != vehiculoId) return CorregirVehiculoPlacasDuplicadas();
    }
    if (vinNormalizado != null) {
      final existente = await _repository.obtenerPorVin(vinNormalizado);
      if (existente != null && existente.id != vehiculoId) return CorregirVehiculoVinDuplicado();
    }

    try {
      final actualizado = await _repository.corregir(
        vehiculoId: vehiculoId,
        marca: marca,
        modelo: modelo,
        anio: anio,
        color: color,
        placas: placasNormalizadas ?? (limpiarPlacas ? null : placas),
        vin: vinNormalizado ?? (limpiarVin ? null : vin),
        numeroMotor: numeroMotor,
        tipoVehiculo: tipoVehiculo,
        fechaAdquisicion: fechaAdquisicion,
        costoAdquisicion: costoAdquisicion,
        observaciones: observaciones,
        limpiarAnio: limpiarAnio,
        limpiarColor: limpiarColor,
        limpiarPlacas: limpiarPlacas,
        limpiarVin: limpiarVin,
        limpiarNumeroMotor: limpiarNumeroMotor,
        limpiarFechaAdquisicion: limpiarFechaAdquisicion,
        limpiarCostoAdquisicion: limpiarCostoAdquisicion,
        limpiarObservaciones: limpiarObservaciones,
      );
      return CorregirVehiculoExitoso(actualizado);
    } catch (e) {
      return CorregirVehiculoErrorInesperado(e.toString());
    }
  }
}
