/// Campo de [ServicioBorrador] (o de sus relaciones) que puede fallar la
/// validación. `fechaTermino` no aparece aquí: solo se captura vía la
/// acción de terminar (`CambiarEstatusServicioUseCase`), nunca desde el
/// formulario general — ver `CambiarEstatusServicioFechaTerminoInvalida`.
enum CampoServicio { nombre, cliente, tipoServicio, fechaInicio }

enum CodigoErrorServicio { requerido, noExiste, clienteNoDisponible }

class ErrorCampoServicio {
  const ErrorCampoServicio({required this.campo, required this.codigo});

  final CampoServicio campo;
  final CodigoErrorServicio codigo;
}

/// Busca el error (si existe) asociado a un campo específico — para que
/// cada `RisegTextField`/`RisegSelect`/`RisegDateField` muestre solo el
/// suyo.
ErrorCampoServicio? errorParaCampoServicio(List<ErrorCampoServicio> errores, CampoServicio campo) {
  for (final error in errores) {
    if (error.campo == campo) return error;
  }
  return null;
}
