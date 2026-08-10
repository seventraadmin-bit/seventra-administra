import 'package:drift/drift.dart';
import 'package:riseg_one/core/codigos/generar_numero_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
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

class CrearEmpleadoCodigoPostalFiscalInvalido extends CrearEmpleadoResultado {}

/// Se proporcionaron `servicioId` y `sucursalId` a la vez — la
/// adscripción es Servicio *o* Sucursal, nunca ambas (Etapa 5D).
class CrearEmpleadoAdscripcionAmbigua extends CrearEmpleadoResultado {}

class CrearEmpleadoServicioNoExiste extends CrearEmpleadoResultado {}

class CrearEmpleadoServicioNoActivo extends CrearEmpleadoResultado {}

/// El Servicio de adscripción no tiene `sueldoMensualReferenciaPersonal`
/// capturado y tampoco se capturó una excepción individual
/// (`sueldoMensualAsignacion`) — mismo criterio que
/// `AsignarEmpleadoServicioSueldoRequerido` (Etapa 6B).
class CrearEmpleadoSueldoAsignacionRequerido extends CrearEmpleadoResultado {}

class CrearEmpleadoSueldoAsignacionInvalido extends CrearEmpleadoResultado {}

class CrearEmpleadoBonoAsignacionInvalido extends CrearEmpleadoResultado {}

/// Datos bancarios (Etapa 6A): se capturó algo pero falta el banco, o
/// falta tanto tarjeta/cuenta como CLABE.
class CrearEmpleadoDatosBancariosInvalidos extends CrearEmpleadoResultado {}

class CrearEmpleadoSueldoAdministrativoInvalido extends CrearEmpleadoResultado {}

class CrearEmpleadoBonoAdministrativoInvalido extends CrearEmpleadoResultado {}

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
  CrearEmpleadoUseCase(this._repository, this._generarNumero, this._validator, this._servicioRepository);

  final EmpleadoRepository _repository;
  final GenerarNumeroUseCase _generarNumero;
  final EmpleadoValidator _validator;
  final ServicioRepository _servicioRepository;

  Future<CrearEmpleadoResultado> ejecutar({
    required String nombres,
    required String apellidoPaterno,
    String? apellidoMaterno,
    required SexoEmpleado sexo,
    required DateTime fechaNacimiento,
    required String curp,
    required String rfc,
    String? codigoPostalFiscal,
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
    // --- Adscripción (Etapa 5D): Servicio *o* Sucursal, nunca ambas.
    // `servicioId`/`turnoId` nunca se guardan en Empleado — crean la
    // `AsignacionServicio` inicial dentro de la misma transacción
    // (ver `EmpleadoRepositoryImpl.crear`). ---
    String? servicioId,
    String? turnoId,
    // Excepción individual de sueldo/bono para la asignación inicial
    // (Etapa 6B) — solo relevante cuando `servicioId != null`; si se
    // omite, se precarga desde
    // `Servicio.sueldoMensualReferenciaPersonal`/
    // `bonoMensualReferenciaPersonal`. Mismo criterio que
    // `AsignarEmpleadoServicioUseCase`.
    int? sueldoMensualAsignacion,
    int? bonoMensualAsignacion,
    String? sucursalId,
    // --- Datos bancarios (Etapa 6A) — todo opcional; si se captura
    // algo, banco es obligatorio y se necesita al menos uno de
    // tarjeta/cuenta o CLABE. ---
    String? bancoId,
    String? numeroCuentaTarjeta,
    String? clabe,
    // --- Condición laboral administrativa (Etapa 6A) — solo relevante
    // para empleados sin AsignacionServicio; ver doc comment de
    // `Empleado`. ---
    int? sueldoMensualAdministrativo,
    int? bonoMensualAdministrativo,
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
    if (codigoPostalFiscal != null &&
        codigoPostalFiscal.trim().isNotEmpty &&
        !_validator.codigoPostalFiscalValido(codigoPostalFiscal)) {
      return CrearEmpleadoCodigoPostalFiscalInvalido();
    }
    if (!_validator.nssValido(nss)) return CrearEmpleadoNssInvalido();
    if (!_validator.fechaNacimientoValida(fechaNacimiento)) return CrearEmpleadoFechaNacimientoInvalida();
    if (!_validator.fechaIngresoValida(fechaIngreso, fechaNacimiento)) return CrearEmpleadoFechaIngresoInvalida();
    if (aniosExperienciaSeguridad < 0) return CrearEmpleadoExperienciaInvalida();
    if (mesesExperienciaAdicionales != null && (mesesExperienciaAdicionales < 0 || mesesExperienciaAdicionales > 11)) {
      return CrearEmpleadoExperienciaInvalida();
    }
    if (!_validator.datosBancariosValidos(bancoId: bancoId, numeroCuentaTarjeta: numeroCuentaTarjeta, clabe: clabe)) {
      return CrearEmpleadoDatosBancariosInvalidos();
    }
    if (!_validator.sueldoAdministrativoValido(sueldoMensualAdministrativo)) {
      return CrearEmpleadoSueldoAdministrativoInvalido();
    }
    if (!_validator.bonoAdministrativoValido(bonoMensualAdministrativo)) {
      return CrearEmpleadoBonoAdministrativoInvalido();
    }

    if (servicioId != null && sucursalId != null) return CrearEmpleadoAdscripcionAmbigua();
    int? sueldoResuelto;
    int? bonoResuelto;
    if (servicioId != null) {
      final servicio = await _servicioRepository.obtenerPorId(servicioId);
      if (servicio == null) return CrearEmpleadoServicioNoExiste();
      if (EstatusServicio.values.byName(servicio.estatus) != EstatusServicio.activo) {
        return CrearEmpleadoServicioNoActivo();
      }

      sueldoResuelto = sueldoMensualAsignacion ?? servicio.sueldoMensualReferenciaPersonal;
      if (sueldoResuelto == null) return CrearEmpleadoSueldoAsignacionRequerido();
      if (sueldoResuelto <= 0) return CrearEmpleadoSueldoAsignacionInvalido();

      bonoResuelto = bonoMensualAsignacion ?? servicio.bonoMensualReferenciaPersonal ?? 0;
      if (bonoResuelto < 0) return CrearEmpleadoBonoAsignacionInvalido();
    }

    try {
      final numeroResultado = await _generarNumero.ejecutar('empleado');
      final numeroEmpleado = numeroResultado.when(ok: (n) => n, failure: (f) => throw StateError(f.message));

      final empleado = await _repository.crear(
        EmpleadoCompanion.insert(
          numeroEmpleado: numeroEmpleado,
          nombres: nombres.trim(),
          apellidoPaterno: apellidoPaterno.trim(),
          apellidoMaterno: Value(_vacioANull(apellidoMaterno)),
          sexo: sexo.name,
          fechaNacimiento: fechaNacimiento,
          curp: curp.trim().toUpperCase(),
          rfc: rfc.trim().toUpperCase(),
          codigoPostalFiscal: Value(_vacioANull(codigoPostalFiscal)),
          nss: nss.trim(),
          estadoCivil: estadoCivil.name,
          nacionalidad: Value(nacionalidad),
          telefono: Value(_vacioANull(telefono)),
          correoElectronico: Value(_vacioANull(correoElectronico)),
          contactoEmergenciaNombre: Value(_vacioANull(contactoEmergenciaNombre)),
          telefonoEmergencia: Value(_vacioANull(telefonoEmergencia)),
          parentescoEmergencia: Value(_vacioANull(parentescoEmergencia)),
          bancoId: Value(bancoId),
          numeroCuentaTarjeta: Value(_vacioANull(numeroCuentaTarjeta)),
          clabe: Value(_vacioANull(clabe)),
          fechaIngreso: fechaIngreso,
          puestoId: Value(puestoId),
          empresaId: Value(empresaId),
          sucursalId: Value(sucursalId),
          sueldoMensualAdministrativo: Value(sueldoMensualAdministrativo),
          bonoMensualAdministrativo: Value(bonoMensualAdministrativo),
          observaciones: Value(_vacioANull(observaciones)),
          nivelEstudios: Value(nivelEstudios?.name),
          observacionesEscolaridad: Value(_vacioANull(observacionesEscolaridad)),
          aniosExperienciaSeguridad: aniosExperienciaSeguridad,
          mesesExperienciaAdicionales: Value(mesesExperienciaAdicionales),
          ultimoPuestoDesempenado: Value(_vacioANull(ultimoPuestoDesempenado)),
          resumenExperiencia: Value(_vacioANull(resumenExperiencia)),
          observacionesExperiencia: Value(_vacioANull(observacionesExperiencia)),
        ),
        servicioIdAsignacion: servicioId,
        turnoIdAsignacion: turnoId,
        sueldoMensualAsignacion: sueldoResuelto,
        bonoMensualAsignacion: bonoResuelto,
      );
      return CrearEmpleadoExitoso(empleado);
    } catch (e) {
      return CrearEmpleadoErrorInesperado(e.toString());
    }
  }
}
