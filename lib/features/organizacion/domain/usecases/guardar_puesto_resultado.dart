import 'package:riseg_one/core/database/app_database.dart';

import 'puesto_errors.dart';

/// Resultado compartido por `CrearPuestoUseCase` y
/// `ActualizarPuestoUseCase` — ambos validan con el mismo
/// `PuestoValidator` y deben poder mostrar sus errores exactamente
/// igual en la pantalla.
sealed class GuardarPuestoResultado {}

class GuardarPuestoExitoso extends GuardarPuestoResultado {
  GuardarPuestoExitoso(this.puesto);
  final PuestoData puesto;
}

class GuardarPuestoErroresValidacion extends GuardarPuestoResultado {
  GuardarPuestoErroresValidacion(this.errores);
  final List<ErrorCampoPuesto> errores;
}

class GuardarPuestoErrorInesperado extends GuardarPuestoResultado {
  GuardarPuestoErrorInesperado(this.mensaje);
  final String mensaje;
}
