import 'package:riseg_one/core/database/app_database.dart';

import 'servicio_errors.dart';

/// Resultado compartido por `CrearServicioUseCase` y
/// `ActualizarServicioUseCase` — evita duplicar el tipo de error entre
/// alta y edición (mismo patrón que `GuardarPuestoResultado`/
/// `GuardarEntidadFiscalResultado`).
sealed class GuardarServicioResultado {}

class GuardarServicioExitoso extends GuardarServicioResultado {
  GuardarServicioExitoso(this.servicio);
  final ServicioData servicio;
}

class GuardarServicioErroresValidacion extends GuardarServicioResultado {
  GuardarServicioErroresValidacion(this.errores);
  final List<ErrorCampoServicio> errores;
}

/// Corregir un Servicio exige explicar por qué.
class GuardarServicioMotivoRequerido extends GuardarServicioResultado {}

class GuardarServicioErrorInesperado extends GuardarServicioResultado {
  GuardarServicioErrorInesperado(this.mensaje);
  final String mensaje;
}
