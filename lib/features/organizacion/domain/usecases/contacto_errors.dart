/// Campo de [ContactoBorrador] que puede fallar la validación.
enum CampoContacto { nombre, tipo, medioContacto }

enum CodigoErrorContacto { requerido, formatoInvalido }

class ErrorCampoContacto {
  const ErrorCampoContacto({required this.campo, required this.codigo});

  final CampoContacto campo;
  final CodigoErrorContacto codigo;
}

/// Busca el error (si existe) asociado a un campo específico — para que
/// cada `RisegTextField`/`RisegSelect` muestre solo el suyo.
ErrorCampoContacto? errorParaCampoContacto(List<ErrorCampoContacto> errores, CampoContacto campo) {
  for (final error in errores) {
    if (error.campo == campo) return error;
  }
  return null;
}
