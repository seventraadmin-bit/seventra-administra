import 'package:riseg_one/core/validation/direccion_validator.dart';

/// Errores estructurados de [GuardarExpedienteClienteUseCase] — sellada
/// porque las dos secciones (datos generales, dirección de referencia)
/// tienen formas de error genuinamente distintas. `ErrorDireccionCliente`
/// reutiliza directamente el [ErrorCampoDireccion] de `core/validation` —
/// no inventa un envoltorio redundante (mismo patrón que
/// `ErrorDireccionSucursal`).
sealed class ErrorExpedienteCliente {}

class ErrorNombreComercialRequerido extends ErrorExpedienteCliente {}

class ErrorDireccionCliente extends ErrorExpedienteCliente {
  ErrorDireccionCliente(this.error);
  final ErrorCampoDireccion error;
}
