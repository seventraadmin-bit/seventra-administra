import 'package:drift/drift.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';

import '../repositories/empleado_repository.dart';
import 'empleado_validator.dart';

sealed class CrearEmpleadoResultado {}

class CrearEmpleadoExitoso extends CrearEmpleadoResultado {
  CrearEmpleadoExitoso(this.empleado);
  final EmpleadoData empleado;
}

class CrearEmpleadoNombresRequerido extends CrearEmpleadoResultado {}

class CrearEmpleadoApellidoPaternoRequerido extends CrearEmpleadoResultado {}

class CrearEmpleadoCurpInvalido extends CrearEmpleadoResultado {}

class CrearEmpleadoRfcInvalido extends CrearEmpleadoResultado {}

class CrearEmpleadoNssInvalido extends CrearEmpleadoResultado {}

class CrearEmpleadoFechaNacimientoInvalida extends CrearEmpleadoResultado {}

class CrearEmpleadoFechaIngresoInvalida extends CrearEmpleadoResultado {}

class CrearEmpleadoExperienciaInvalida extends CrearEmpleadoResultado {}

class CrearEmpleadoErrorInesperado extends CrearEmpleadoResultado {
  CrearEmpleadoErrorInesperado(this.mensaje);
  final String mensaje;
}

String? _vacioANull(String? valor) {
  final recortado = valor?.trim();
  return (recortado == null || recortado.isEmpty) ? null : recortado;
}

/// Registra el expediente de un Empleado (Etapa 5A) — información
/// general, contacto, laboral, escolaridad y experiencia general en
/// seguridad privada (sin historial estructurado por empleador,
/// Resolución explícita de Marlon). Domicilio y documentación se
/// capturan por separado (`GuardarDomicilioEmpleadoUseCase`,
/// `AdjuntarDocumentoEmpleadoUseCase`) — un expediente puede existir
/// sin ninguno de los dos todavía.
class CrearEmpleadoUseCase {
  CrearEmpleadoUseCase(this._repository, this._generarCodigo, this._validator);

  final EmpleadoRepository _repository;
  final GenerarCodigoUseCase _generarCodigo;
  final EmpleadoValidator _validator;

  Future<CrearEmpleadoResultado> ejecutar({
    required String nombres,
    required String apellidoPaterno,
    String? apellidoMaterno,
    required SexoEmpleado sexo,
    required DateTime fechaNacimiento,
    required String curp,
    required String rfc,
    required String nss,
    required EstadoCivilEmpleado estadoCivil,
    String nacionalidad = 'Mexicana',
    String? telefono,
    String? correoElectronico,
    String? contactoEmergenciaNombre,
    String? telefonoEmergencia,
    String? parentescoEmergencia,
    required DateTime fechaIngreso,
    String? puestoId,
    String? empresaId,
    String? sucursalId,
    String? observaciones,
    NivelEstudiosEmpleado? nivelEstudios,
    String? observacionesEscolaridad,
    required int aniosExperienciaSeguridad,
    int? mesesExperienciaAdicionales,
    String? ultimoPuestoDesempenado,
    String? resumenExperiencia,
    String? observacionesExperiencia,
    String? actor,
  }) async {
    if (nombres.trim().isEmpty) return CrearEmpleadoNombresRequerido();
    if (apellidoPaterno.trim().isEmpty) return CrearEmpleadoApellidoPaternoRequerido();
    if (!_validator.curpValido(curp)) return CrearEmpleadoCurpInvalido();
    if (!_validator.rfcValido(rfc)) return CrearEmpleadoRfcInvalido();
    if (!_validator.nssValido(nss)) return CrearEmpleadoNssInvalido();
    if (!_validator.fechaNacimientoValida(fechaNacimiento)) return CrearEmpleadoFechaNacimientoInvalida();
    if (!_validator.fechaIngresoValida(fechaIngreso, fechaNacimiento)) return CrearEmpleadoFechaIngresoInvalida();
    if (aniosExperienciaSeguridad < 0) return CrearEmpleadoExperienciaInvalida();
    if (mesesExperienciaAdicionales != null && (mesesExperienciaAdicionales < 0 || mesesExperienciaAdicionales > 11)) {
      return CrearEmpleadoExperienciaInvalida();
    }

    try {
      final codigoResultado = await _generarCodigo.ejecutar('empleado');
      final codigoEmpleado = codigoResultado.when(ok: (c) => c, failure: (f) => throw StateError(f.message));

      final empleado = await _repository.crear(
        EmpleadoCompanion.insert(
          codigoEmpleado: codigoEmpleado,
          nombres: nombres.trim(),
          apellidoPaterno: apellidoPaterno.trim(),
          apellidoMaterno: Value(_vacioANull(apellidoMaterno)),
          sexo: sexo.name,
          fechaNacimiento: fechaNacimiento,
          curp: curp.trim().toUpperCase(),
          rfc: rfc.trim().toUpperCase(),
          nss: nss.trim(),
          estadoCivil: estadoCivil.name,
          nacionalidad: Value(nacionalidad),
          telefono: Value(_vacioANull(telefono)),
          correoElectronico: Value(_vacioANull(correoElectronico)),
          contactoEmergenciaNombre: Value(_vacioANull(contactoEmergenciaNombre)),
          telefonoEmergencia: Value(_vacioANull(telefonoEmergencia)),
          parentescoEmergencia: Value(_vacioANull(parentescoEmergencia)),
          fechaIngreso: fechaIngreso,
          puestoId: Value(puestoId),
          empresaId: Value(empresaId),
          sucursalId: Value(sucursalId),
          observaciones: Value(_vacioANull(observaciones)),
          nivelEstudios: Value(nivelEstudios?.name),
          observacionesEscolaridad: Value(_vacioANull(observacionesEscolaridad)),
          aniosExperienciaSeguridad: aniosExperienciaSeguridad,
          mesesExperienciaAdicionales: Value(mesesExperienciaAdicionales),
          ultimoPuestoDesempenado: Value(_vacioANull(ultimoPuestoDesempenado)),
          resumenExperiencia: Value(_vacioANull(resumenExperiencia)),
          observacionesExperiencia: Value(_vacioANull(observacionesExperiencia)),
        ),
      );
      return CrearEmpleadoExitoso(empleado);
    } catch (e) {
      return CrearEmpleadoErrorInesperado(e.toString());
    }
  }
}
