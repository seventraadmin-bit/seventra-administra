/// Campo de [ClientePortalBorrador] (o del Cliente propietario) que
/// puede fallar la validación.
enum CampoClientePortal { cliente, nombre }

enum CodigoErrorClientePortal { requerido, clienteInactivo }

class ErrorCampoClientePortal {
  const ErrorCampoClientePortal({required this.campo, required this.codigo});

  final CampoClientePortal campo;
  final CodigoErrorClientePortal codigo;
}

/// Busca el error (si existe) asociado a un campo específico — para que
/// cada `RisegTextField` muestre solo el suyo.
ErrorCampoClientePortal? errorParaCampoClientePortal(
  List<ErrorCampoClientePortal> errores,
  CampoClientePortal campo,
) {
  for (final error in errores) {
    if (error.campo == campo) return error;
  }
  return null;
}
