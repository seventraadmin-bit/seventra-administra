import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';
import 'package:riseg_one/features/organizacion/domain/shared/direccion_input.dart';

import '../repositories/empleado_repository.dart';

/// Resultado de [GuardarDomicilioEmpleadoUseCase] — propio, mismo
/// criterio que `GuardarDomicilioFiscalUseCase`: el domicilio se
/// administra completamente aparte del resto del expediente.
sealed class GuardarDomicilioEmpleadoResultado {}

class GuardarDomicilioEmpleadoExitoso extends GuardarDomicilioEmpleadoResultado {
  GuardarDomicilioEmpleadoExitoso(this.domicilio);
  final DireccionData? domicilio;
}

class GuardarDomicilioEmpleadoErroresValidacion extends GuardarDomicilioEmpleadoResultado {
  GuardarDomicilioEmpleadoErroresValidacion(this.errores);
  final List<ErrorCampoDireccion> errores;
}

class GuardarDomicilioEmpleadoNoExiste extends GuardarDomicilioEmpleadoResultado {}

class GuardarDomicilioEmpleadoErrorInesperado extends GuardarDomicilioEmpleadoResultado {
  GuardarDomicilioEmpleadoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Captura/edita/limpia el domicilio de un Empleado ya existente —
/// reutiliza por completo la infraestructura de `Direccion`
/// (`DireccionValidator`/`DireccionBorrador`/`DireccionInput`), mismo
/// mecanismo que `GuardarDomicilioFiscalUseCase`. Un domicilio vacío
/// nunca se persiste; uno parcialmente incompleto es rechazado por
/// `DireccionValidator`; si había uno y se vacía por completo, el
/// repositorio lo archiva — nunca un `hard delete`.
class GuardarDomicilioEmpleadoUseCase {
  GuardarDomicilioEmpleadoUseCase(this._repository);

  final EmpleadoRepository _repository;

  Future<GuardarDomicilioEmpleadoResultado> ejecutar({
    required String empleadoId,
    required DireccionBorrador? domicilio,
    String? actorUsuarioId,
  }) async {
    final empleado = await _repository.obtenerPorId(empleadoId);
    if (empleado == null) return GuardarDomicilioEmpleadoNoExiste();

    DireccionInput? validado;
    if (domicilio != null) {
      final r = DireccionValidator.validar(domicilio);
      if (r.errores.isNotEmpty) {
        return GuardarDomicilioEmpleadoErroresValidacion(r.errores);
      }
      final d = r.resultado;
      if (d != null) {
        validado = DireccionInput(
          calle: d.calle,
          numeroExterior: d.numeroExterior,
          numeroInterior: d.numeroInterior,
          colonia: d.colonia,
          municipioAlcaldia: d.municipioAlcaldia,
          ciudadLocalidad: d.ciudadLocalidad,
          estado: d.estado,
          codigoPostal: d.codigoPostal,
          pais: d.pais,
          referencias: d.referencias,
        );
      }
    }

    try {
      final resultado = await _repository.guardarDomicilio(empleadoId, validado, actorUsuarioId: actorUsuarioId);
      return GuardarDomicilioEmpleadoExitoso(resultado);
    } catch (e) {
      return GuardarDomicilioEmpleadoErrorInesperado(e.toString());
    }
  }
}
