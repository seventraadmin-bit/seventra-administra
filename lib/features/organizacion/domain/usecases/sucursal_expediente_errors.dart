import 'package:riseg_one/core/validation/direccion_validator.dart';

/// Día de la semana para errores de Horario. `index` coincide con
/// `HorarioDetalle.diaSemana` (0 = lunes ... 6 = domingo).
enum DiaSemana { lunes, martes, miercoles, jueves, viernes, sabado, domingo }

enum CodigoErrorHorario { horaInicioRequerida, horaFinRequerida, horasIguales }

/// Errores estructurados de [GuardarExpedienteSucursalUseCase] — una
/// jerarquía sellada en vez de un único enum plano, porque las tres
/// secciones (datos generales, dirección, horario) tienen formas de
/// error genuinamente distintas. `ErrorDireccionSucursal` reutiliza
/// directamente el [ErrorCampoDireccion] de `core/validation` — no
/// inventa un envoltorio redundante.
sealed class ErrorExpedienteSucursal {}

class ErrorTipoSucursalRequerido extends ErrorExpedienteSucursal {}

class ErrorDireccionSucursal extends ErrorExpedienteSucursal {
  ErrorDireccionSucursal(this.error);
  final ErrorCampoDireccion error;
}

class ErrorHorarioSucursal extends ErrorExpedienteSucursal {
  ErrorHorarioSucursal({required this.dia, required this.codigo});
  final DiaSemana dia;
  final CodigoErrorHorario codigo;
}
