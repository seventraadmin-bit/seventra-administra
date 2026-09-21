/// Un plazo del plan de recuperación — solo el importe, la fecha se
/// resuelve aparte (ver `generarFechasCuotas`).
class ImporteCuota {
  const ImporteCuota({required this.numeroCuota, required this.importe});

  final int numeroCuota;
  final int importe;
}

/// Reparte [importeOriginal] (centavos) en [numeroCuotas] partes que
/// suman EXACTAMENTE el original — nunca se pierde un centavo por
/// redondeo. Cociente entero para todas las cuotas salvo las últimas,
/// que absorben el residuo de la división (ej. `$1,000 / 3` →
/// `$333.33 + $333.33 + $333.34`, nunca `$333.33 × 3 = $999.99`).
///
/// Función pura, sin BD ni Flutter — reutilizada tanto por el
/// diálogo "Registrar descuento" (previsualización en vivo, mismo
/// cálculo que se va a persistir) como por
/// `ReprogramarCuotasPendientesUseCase`.
List<ImporteCuota> dividirEnCuotas({
  required int importeOriginal,
  required int numeroCuotas,
}) {
  if (numeroCuotas <= 0) {
    throw ArgumentError.value(
      numeroCuotas,
      'numeroCuotas',
      'debe ser mayor a cero',
    );
  }
  if (importeOriginal <= 0) {
    throw ArgumentError.value(
      importeOriginal,
      'importeOriginal',
      'debe ser mayor a cero',
    );
  }

  final base = importeOriginal ~/ numeroCuotas;
  final residuo = importeOriginal - (base * numeroCuotas);

  return [
    for (var i = 0; i < numeroCuotas; i++)
      ImporteCuota(
        numeroCuota: i + 1,
        // El residuo se reparte de a un centavo por cuota, empezando
        // por las ÚLTIMAS — así una cuota "sugerida redonda" (ej. la
        // primera de $500 de un préstamo de $3,000/6) nunca se ve
        // alterada por el ajuste de centavos si no hace falta.
        importe: base + (i >= numeroCuotas - residuo ? 1 : 0),
      ),
  ];
}
