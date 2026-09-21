/// Totales derivados de un renglón de Nómina — única fórmula del
/// dominio (Etapa 15, calculadora auditable), antes duplicada en 4
/// lugares idénticos dentro de `NominaRepositoryImpl`. `faltas` es
/// siempre independiente de `diasPagables` (una falta nunca reduce los
/// días pagables, solo genera esta deducción) — nunca hay doble
/// descuento porque `importeBase` ya viene resuelto sin considerar
/// faltas en ningún punto previo.
class TotalesRenglonNomina {
  const TotalesRenglonNomina({required this.descuentoPorFaltas, required this.totalAPagar});

  final int descuentoPorFaltas;
  final int totalAPagar;
}

/// `totalAPagar = importeBase + bono + tiempoExtra − prestamo −
/// descuentoPorFaltas − otrosDescuentos − descuentosInventario −
/// descuentosProgramados`. `descuentoPorFaltas = faltas × pagoPorDia`.
/// Pura, sin acceso a BD — única fuente de verdad reutilizada por el
/// repositorio (escritura) y por `ActualizarRenglonNominaUseCase`
/// (validación de una distribución manual contra el total prospectivo,
/// antes de escribir nada).
///
/// [descuentosProgramados] (Etapa 15, "Descuentos Programados al
/// Personal" — préstamos/botas) es la suma de `DescuentoProgramadoCuota`
/// reservadas/aplicadas a este renglón — mismo criterio exacto que
/// [descuentosInventario], resuelto SIEMPRE después de éste contra el
/// neto ya disminuido por Inventario (nunca ambos pools contra el mismo
/// neto de forma independiente — ver
/// `NominaRepositoryImpl._resolverCuotasProgramadasAplicables`).
TotalesRenglonNomina calcularTotalesRenglonNomina({
  required int importeBase,
  required int pagoPorDia,
  required int bono,
  required int tiempoExtra,
  required int prestamo,
  required int faltas,
  required int otrosDescuentos,
  required int descuentosInventario,
  required int descuentosProgramados,
}) {
  final descuentoPorFaltas = faltas * pagoPorDia;
  final totalAPagar = importeBase +
      bono +
      tiempoExtra -
      prestamo -
      descuentoPorFaltas -
      otrosDescuentos -
      descuentosInventario -
      descuentosProgramados;
  return TotalesRenglonNomina(descuentoPorFaltas: descuentoPorFaltas, totalAPagar: totalAPagar);
}
