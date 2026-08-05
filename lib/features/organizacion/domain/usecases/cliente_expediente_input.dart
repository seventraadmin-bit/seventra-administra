import 'package:riseg_one/core/validation/direccion_validator.dart';

/// Datos generales del Cliente tal como llegan del formulario.
class ClienteDatosGeneralesInput {
  const ClienteDatosGeneralesInput({required this.nombreComercial, this.observaciones});

  final String nombreComercial;
  final String? observaciones;
}

/// Entrada completa de `GuardarExpedienteClienteUseCase`.
///
/// `direccionReferencia` reutiliza directamente `DireccionBorrador` de
/// `core/validation` — mismo shape que usan Empresa y Sucursal, sin
/// envoltorio propio de Cliente.
class ClienteExpedienteInput {
  const ClienteExpedienteInput({required this.datosGenerales, this.direccionReferencia});

  final ClienteDatosGeneralesInput datosGenerales;
  final DireccionBorrador? direccionReferencia;
}
