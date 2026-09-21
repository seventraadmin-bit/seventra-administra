import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/deuda_repository.dart';

sealed class CorregirDeudaResultado {}

class CorregirDeudaExitoso extends CorregirDeudaResultado {
  CorregirDeudaExitoso(this.deuda);
  final DeudaData deuda;
}

class CorregirDeudaNoExiste extends CorregirDeudaResultado {}

class CorregirDeudaErrorInesperado extends CorregirDeudaResultado {
  CorregirDeudaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige metadata de una Deuda (Etapa 19) — nunca `tipo`/
/// `importeOriginal`/`saldoActual`/`estatus` (esos solo cambian vía
/// `MovimientoDeuda`), mismo criterio que `CorregirArticuloUseCase`
/// nunca toca `manejaVariante`/`manejaSerie`.
class CorregirDeudaUseCase {
  CorregirDeudaUseCase(this._repository);

  final DeudaRepository _repository;

  Future<CorregirDeudaResultado> ejecutar({
    required String deudaId,
    String? nombre,
    String? acreedor,
    DateTime? fechaOrigen,
    bool limpiarFechaOrigen = false,
    DateTime? fechaVencimiento,
    bool limpiarFechaVencimiento = false,
    int? pagoProgramado,
    bool limpiarPagoProgramado = false,
    String? periodicidad,
    bool limpiarPeriodicidad = false,
    double? tasaInteres,
    bool limpiarTasaInteres = false,
    String? referencia,
    String? observaciones,
    String? tarjetaUltimosDigitos,
    int? tarjetaLimiteCredito,
    int? tarjetaDiaCorte,
    int? tarjetaDiaPago,
    int? tarjetaPagoMinimo,
    String? tarjetaReglaFechaPago,
    int? tarjetaDiasDespuesCorte,
    String? tarjetaTipoTasa,
    bool limpiarTarjetaTipoTasa = false,
    String? tarjetaTasaReferencia,
    double? tarjetaTasaDiferencial,
    bool? tarjetaTasaMasIva,
    String? tarjetaTasaDescripcion,
    bool limpiarTasaVariable = false,
    double? tarjetaCat,
    bool? tarjetaCatIncluyeIva,
    bool limpiarCat = false,
    DateTime? tarjetaVencimientoCubiertoHasta,
    bool limpiarTarjetaVencimientoCubierto = false,
  }) async {
    final existente = await _repository.obtenerPorId(deudaId);
    if (existente == null) return CorregirDeudaNoExiste();

    try {
      final deuda = await _repository.corregir(
        deudaId: deudaId,
        nombre: nombre,
        acreedor: acreedor,
        fechaOrigen: fechaOrigen,
        limpiarFechaOrigen: limpiarFechaOrigen,
        fechaVencimiento: fechaVencimiento,
        limpiarFechaVencimiento: limpiarFechaVencimiento,
        pagoProgramado: pagoProgramado,
        limpiarPagoProgramado: limpiarPagoProgramado,
        periodicidad: periodicidad,
        limpiarPeriodicidad: limpiarPeriodicidad,
        tasaInteres: tasaInteres,
        limpiarTasaInteres: limpiarTasaInteres,
        referencia: referencia,
        observaciones: observaciones,
        tarjetaUltimosDigitos: tarjetaUltimosDigitos,
        tarjetaLimiteCredito: tarjetaLimiteCredito,
        tarjetaDiaCorte: tarjetaDiaCorte,
        tarjetaDiaPago: tarjetaDiaPago,
        tarjetaPagoMinimo: tarjetaPagoMinimo,
        tarjetaReglaFechaPago: tarjetaReglaFechaPago,
        tarjetaDiasDespuesCorte: tarjetaDiasDespuesCorte,
        tarjetaTipoTasa: tarjetaTipoTasa,
        limpiarTarjetaTipoTasa: limpiarTarjetaTipoTasa,
        tarjetaTasaReferencia: tarjetaTasaReferencia,
        tarjetaTasaDiferencial: tarjetaTasaDiferencial,
        tarjetaTasaMasIva: tarjetaTasaMasIva,
        tarjetaTasaDescripcion: tarjetaTasaDescripcion,
        limpiarTasaVariable: limpiarTasaVariable,
        tarjetaCat: tarjetaCat,
        tarjetaCatIncluyeIva: tarjetaCatIncluyeIva,
        limpiarCat: limpiarCat,
        tarjetaVencimientoCubiertoHasta: tarjetaVencimientoCubiertoHasta,
        limpiarTarjetaVencimientoCubierto: limpiarTarjetaVencimientoCubierto,
      );
      return CorregirDeudaExitoso(deuda);
    } catch (e) {
      return CorregirDeudaErrorInesperado(e.toString());
    }
  }
}
