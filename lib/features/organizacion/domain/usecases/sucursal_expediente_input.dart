import 'package:riseg_one/core/validation/direccion_validator.dart';

import '../shared/horario_input.dart';

/// Datos generales de la Sucursal tal como llegan del formulario.
class SucursalDatosGeneralesInput {
  const SucursalDatosGeneralesInput({required this.nombre, required this.tipoSucursalId});

  final String nombre;
  final String tipoSucursalId;
}

/// Entrada completa de `GuardarExpedienteSucursalUseCase`.
///
/// `direccionPrincipal` reutiliza directamente `DireccionBorrador` de
/// `core/validation` — no hace falta un envoltorio propio de Sucursal,
/// el shape es exactamente el mismo que usa Empresa.
class SucursalExpedienteInput {
  const SucursalExpedienteInput({
    required this.datosGenerales,
    this.direccionPrincipal,
    this.horario,
  });

  final SucursalDatosGeneralesInput datosGenerales;
  final DireccionBorrador? direccionPrincipal;
  final HorarioSemanalBorrador? horario;
}
