import 'package:riseg_one/core/database/app_database.dart';

import 'contacto_errors.dart';

/// Resultado compartido por `AgregarContactoUseCase` y
/// `ActualizarContactoUseCase` — evita duplicar el tipo de error entre
/// alta y edición (mismo motivo que `GuardarPuestoResultado`).
sealed class GuardarContactoResultado {}

class GuardarContactoExitoso extends GuardarContactoResultado {
  GuardarContactoExitoso(this.contacto);
  final ContactoData contacto;
}

class GuardarContactoErroresValidacion extends GuardarContactoResultado {
  GuardarContactoErroresValidacion(this.errores);
  final List<ErrorCampoContacto> errores;
}

class GuardarContactoErrorInesperado extends GuardarContactoResultado {
  GuardarContactoErrorInesperado(this.mensaje);
  final String mensaje;
}
