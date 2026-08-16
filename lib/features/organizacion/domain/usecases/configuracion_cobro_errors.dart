/// Campo de [ConfiguracionCobroBorrador] que puede fallar la validación.
enum CampoConfiguracionCobro {
  tipoDocumento,
  frecuencia,
  diaInicioPeriodo,
  agrupacion,
  metodo,
  requiereComplemento,
  entidadFiscal,
  clientePortal,
  fechaInicioVigencia,
  correos,

  /// Se usa cuando el conflicto es contra el tratamiento de IVA de las
  /// líneas comerciales vigentes del Servicio (Etapa 4H.1, Resolución
  /// D/G) — el campo en conflicto no es propio de esta configuración.
  tratamientoIvaLineasComerciales,
}

enum CodigoErrorConfiguracionCobro {
  requerido,
  noExiste,
  inactivo,

  /// CFDI sin Entidad fiscal capturada.
  entidadFiscalRequeridaParaCfdi,

  /// Recibo debe usar `metodo == noAplica`.
  metodoInvalidoParaRecibo,

  /// `metodo == ppd` exige `requiereComplemento == true`.
  complementoRequeridoParaPpd,

  /// CFDI con al menos una línea comercial vigente en `noAplica`.
  cfdiIncompatibleConIvaNoAplica,

  /// Recibo con al menos una línea comercial vigente que no sea
  /// `noAplica` (Resolución D: recibo impone `noAplica` como regla).
  reciboRequiereIvaNoAplica,

  fechaAnteriorInicioServicio,

  /// Etapa 4H.2 — ya existe una vigencia de esta Configuración de cobro
  /// con exactamente esa fecha de inicio.
  fechaDuplicada,

  correoInvalido,
}

class ErrorConfiguracionCobro {
  const ErrorConfiguracionCobro({required this.campo, required this.codigo});

  final CampoConfiguracionCobro campo;
  final CodigoErrorConfiguracionCobro codigo;
}

/// Busca el error (si existe) asociado a un campo específico — mismo
/// patrón que `errorParaCampoLineaComercial`.
ErrorConfiguracionCobro? errorParaCampoConfiguracionCobro(
  List<ErrorConfiguracionCobro> errores,
  CampoConfiguracionCobro campo,
) {
  for (final error in errores) {
    if (error.campo == campo) return error;
  }
  return null;
}
