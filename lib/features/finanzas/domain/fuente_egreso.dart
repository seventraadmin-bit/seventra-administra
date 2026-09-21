/// Una cuenta y el importe que aporta a un Egreso — el borrador que
/// los casos de uso entregan al repositorio, antes de existir como
/// fila `EgresoFuente`.
///
/// Un Egreso pagado desde una sola cuenta lleva una sola fuente; no hay
/// un "caso simple" distinto. Esa uniformidad es la que permite que
/// `calcularSaldos` lea siempre el mismo sitio.
class FuenteEgreso {
  const FuenteEgreso({required this.cuentaFinancieraId, required this.importe});

  final String cuentaFinancieraId;

  /// Centavos, siempre `> 0`.
  final int importe;

  @override
  String toString() => 'FuenteEgreso($cuentaFinancieraId, $importe)';
}

/// El reparto no cuadra con el importe del Egreso.
///
/// Es una excepción, como [SaldoInsuficienteException], y por la misma
/// razón: aborta la transacción entera en vez de dejar un Egreso cuyas
/// fuentes no suman lo que dice.
class DistribucionInvalidaException implements Exception {
  DistribucionInvalidaException(this.mensaje);

  final String mensaje;

  @override
  String toString() => 'DistribucionInvalidaException: $mensaje';
}
