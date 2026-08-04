import 'package:riseg_one/core/validation/direccion_validator.dart';

/// Datos generales de la Sucursal tal como llegan del formulario.
class SucursalDatosGeneralesInput {
  const SucursalDatosGeneralesInput({required this.nombre, required this.tipoSucursalId});

  final String nombre;
  final String tipoSucursalId;
}

/// Un día del Horario tal como llega del formulario — sin validar
/// todavía. `horaInicioMinutos`/`horaFinMinutos` son minutos desde
/// medianoche (lo que produce la conversión de `TimeOfDay` en la
/// pantalla; el dominio no depende de Flutter).
class HorarioDiaBorrador {
  const HorarioDiaBorrador({required this.abierto, this.horaInicioMinutos, this.horaFinMinutos});

  final bool abierto;
  final int? horaInicioMinutos;
  final int? horaFinMinutos;
}

/// Siempre exactamente 7 días (índice 0 = lunes ... 6 = domingo).
class HorarioSemanalBorrador {
  const HorarioSemanalBorrador({required this.dias});

  final List<HorarioDiaBorrador> dias;

  bool get estaCompletamenteVacio => dias.every((d) => !d.abierto);
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
