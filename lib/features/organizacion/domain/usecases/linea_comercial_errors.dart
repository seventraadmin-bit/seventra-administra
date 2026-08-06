/// Campo de [LineaComercialBorrador] que puede fallar la validación.
enum CampoLineaComercial {
  puesto,
  modalidadTurno,
  cantidadElementos,
  precioUnitario,
  tratamientoIva,
  fechaInicioVigencia,
  fechaFinVigencia,
}

enum CodigoErrorLineaComercial {
  requerido,
  noExiste,
  inactivo,
  fechaAnteriorInicioServicio,

  /// Etapa 4G.2 — ya existe una vigencia de esta línea con exactamente
  /// esa fecha de inicio.
  fechaDuplicada,

  /// Etapa 4G.2 — la fecha de fin capturada a mano se solaparía con una
  /// vigencia posterior ya registrada (nunca se trunca en silencio un
  /// valor que el usuario escribió explícitamente).
  solapamiento,
}

class ErrorLineaComercial {
  const ErrorLineaComercial({required this.campo, required this.codigo});

  final CampoLineaComercial campo;
  final CodigoErrorLineaComercial codigo;
}

/// Busca el error (si existe) asociado a un campo específico — mismo
/// patrón que `errorParaCampoServicio`.
ErrorLineaComercial? errorParaCampoLineaComercial(List<ErrorLineaComercial> errores, CampoLineaComercial campo) {
  for (final error in errores) {
    if (error.campo == campo) return error;
  }
  return null;
}
