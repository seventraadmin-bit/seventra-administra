/// Campo de [EntidadFiscalBorrador] (o del Cliente propietario) que
/// puede fallar la validación.
enum CampoEntidadFiscal { cliente, razonSocial, rfc }

enum CodigoErrorEntidadFiscal { requerido, formatoInvalido, yaExiste, clienteInactivo }

class ErrorCampoEntidadFiscal {
  const ErrorCampoEntidadFiscal({required this.campo, required this.codigo});

  final CampoEntidadFiscal campo;
  final CodigoErrorEntidadFiscal codigo;
}

/// Busca el error (si existe) asociado a un campo específico — para que
/// cada `RisegTextField` muestre solo el suyo.
ErrorCampoEntidadFiscal? errorParaCampoEntidadFiscal(
  List<ErrorCampoEntidadFiscal> errores,
  CampoEntidadFiscal campo,
) {
  for (final error in errores) {
    if (error.campo == campo) return error;
  }
  return null;
}
