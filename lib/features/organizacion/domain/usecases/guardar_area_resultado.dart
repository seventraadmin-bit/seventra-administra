import 'package:riseg_one/core/database/app_database.dart';

/// Resultado compartido por `CrearAreaUseCase` y `ActualizarAreaUseCase`.
/// Área solo tiene una regla de validación real (nombre requerido) —no
/// se justifica un validador compartido tipo `PuestoValidator` para un
/// único campo.
sealed class GuardarAreaResultado {}

class GuardarAreaExitoso extends GuardarAreaResultado {
  GuardarAreaExitoso(this.area);
  final AreaData area;
}

class GuardarAreaNombreRequerido extends GuardarAreaResultado {}

class GuardarAreaErrorInesperado extends GuardarAreaResultado {
  GuardarAreaErrorInesperado(this.mensaje);
  final String mensaje;
}
