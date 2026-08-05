/// Campo de [LineaComercialBorrador] que puede fallar la validación.
enum CampoLineaComercial { puesto, modalidadTurno, cantidadElementos, precioUnitario, tratamientoIva, fechaInicioVigencia }

enum CodigoErrorLineaComercial { requerido, noExiste, inactivo, fechaAnteriorInicioServicio }

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
