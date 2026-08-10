import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';

import '../repositories/empleado_repository.dart';
import 'empleado_validator.dart';

sealed class CorregirEmpleadoResultado {}

class CorregirEmpleadoExitoso extends CorregirEmpleadoResultado {
  CorregirEmpleadoExitoso(this.empleado);
  final EmpleadoData empleado;
}

class CorregirEmpleadoNoExiste extends CorregirEmpleadoResultado {}

class CorregirEmpleadoCurpInvalido extends CorregirEmpleadoResultado {}

class CorregirEmpleadoRfcInvalido extends CorregirEmpleadoResultado {}

class CorregirEmpleadoNssInvalido extends CorregirEmpleadoResultado {}

class CorregirEmpleadoFechaNacimientoInvalida extends CorregirEmpleadoResultado {}

class CorregirEmpleadoFechaIngresoInvalida extends CorregirEmpleadoResultado {}

class CorregirEmpleadoCodigoPostalFiscalInvalido extends CorregirEmpleadoResultado {}

class CorregirEmpleadoExperienciaInvalida extends CorregirEmpleadoResultado {}

/// Datos bancarios (Etapa 6A): tras aplicar los cambios, se capturó
/// algo pero falta el banco, o falta tanto tarjeta/cuenta como CLABE.
class CorregirEmpleadoDatosBancariosInvalidos extends CorregirEmpleadoResultado {}

class CorregirEmpleadoSueldoAdministrativoInvalido extends CorregirEmpleadoResultado {}

class CorregirEmpleadoBonoAdministrativoInvalido extends CorregirEmpleadoResultado {}

class CorregirEmpleadoErrorInesperado extends CorregirEmpleadoResultado {
  CorregirEmpleadoErrorInesperado(this.mensaje);
  final String mensaje;
}

String? _vacioANull(String? valor) {
  final recortado = valor?.trim();
  return (recortado == null || recortado.isEmpty) ? null : recortado;
}

/// Corrige el expediente de un Empleado (Etapa 5A) — nunca
/// `numeroEmpleado` (inmutable después de creado, mismo criterio que
/// `clienteId` en `ActualizarServicioUseCase`) ni `estatus` (vía
/// `CambiarEstatusEmpleadoUseCase`, acción explícita separada). Cubre
/// datos generales, contacto, laboral, escolaridad y experiencia en un
/// solo flujo — todos son "editar un dato administrativo", mismo
/// criterio que `CorregirPagoUseCase`.
class CorregirEmpleadoUseCase {
  CorregirEmpleadoUseCase(this._repository, this._validator);

  final EmpleadoRepository _repository;
  final EmpleadoValidator _validator;

  Future<CorregirEmpleadoResultado> ejecutar({
    required String empleadoId,
    String? nombres,
    String? apellidoPaterno,
    String? apellidoMaterno,
    SexoEmpleado? sexo,
    DateTime? fechaNacimiento,
    String? curp,
    String? rfc,
    String? codigoPostalFiscal,
    bool limpiarCodigoPostalFiscal = false,
    String? nss,
    EstadoCivilEmpleado? estadoCivil,
    String? nacionalidad,
    String? telefono,
    String? correoElectronico,
    String? contactoEmergenciaNombre,
    String? telefonoEmergencia,
    String? parentescoEmergencia,
    DateTime? fechaIngreso,
    String? puestoId,
    bool limpiarPuesto = false,
    String? empresaId,
    bool limpiarEmpresa = false,
    String? sucursalId,
    bool limpiarSucursal = false,
    String? bancoId,
    bool limpiarBanco = false,
    String? numeroCuentaTarjeta,
    bool limpiarNumeroCuentaTarjeta = false,
    String? clabe,
    bool limpiarClabe = false,
    int? sueldoMensualAdministrativo,
    bool limpiarSueldoMensualAdministrativo = false,
    int? bonoMensualAdministrativo,
    bool limpiarBonoMensualAdministrativo = false,
    String? observaciones,
    NivelEstudiosEmpleado? nivelEstudios,
    String? observacionesEscolaridad,
    int? aniosExperienciaSeguridad,
    int? mesesExperienciaAdicionales,
    String? ultimoPuestoDesempenado,
    String? resumenExperiencia,
    String? observacionesExperiencia,
    required String motivo,
    String? actor,
  }) async {
    final actual = await _repository.obtenerPorId(empleadoId);
    if (actual == null) return CorregirEmpleadoNoExiste();

    if (curp != null && !_validator.curpValido(curp)) return CorregirEmpleadoCurpInvalido();
    if (rfc != null && !_validator.rfcValido(rfc)) return CorregirEmpleadoRfcInvalido();
    if (codigoPostalFiscal != null &&
        codigoPostalFiscal.trim().isNotEmpty &&
        !_validator.codigoPostalFiscalValido(codigoPostalFiscal)) {
      return CorregirEmpleadoCodigoPostalFiscalInvalido();
    }
    if (nss != null && !_validator.nssValido(nss)) return CorregirEmpleadoNssInvalido();

    final nacimientoEfectiva = fechaNacimiento ?? actual.fechaNacimiento;
    if (fechaNacimiento != null && !_validator.fechaNacimientoValida(fechaNacimiento)) {
      return CorregirEmpleadoFechaNacimientoInvalida();
    }
    if (fechaIngreso != null && !_validator.fechaIngresoValida(fechaIngreso, nacimientoEfectiva)) {
      return CorregirEmpleadoFechaIngresoInvalida();
    }
    if (aniosExperienciaSeguridad != null && aniosExperienciaSeguridad < 0) {
      return CorregirEmpleadoExperienciaInvalida();
    }
    if (mesesExperienciaAdicionales != null && (mesesExperienciaAdicionales < 0 || mesesExperienciaAdicionales > 11)) {
      return CorregirEmpleadoExperienciaInvalida();
    }

    // Datos bancarios (Etapa 6A) — se valida el estado *efectivo* tras
    // aplicar los cambios (fusionando con lo ya existente), no solo lo
    // que llega en esta llamada: la regla es sobre el conjunto final.
    final bancoIdEfectivo = limpiarBanco ? null : (bancoId ?? actual.bancoId);
    final numeroCuentaTarjetaEfectivo =
        limpiarNumeroCuentaTarjeta ? null : (numeroCuentaTarjeta != null ? _vacioANull(numeroCuentaTarjeta) : actual.numeroCuentaTarjeta);
    final clabeEfectiva = limpiarClabe ? null : (clabe != null ? _vacioANull(clabe) : actual.clabe);
    if (!_validator.datosBancariosValidos(
      bancoId: bancoIdEfectivo,
      numeroCuentaTarjeta: numeroCuentaTarjetaEfectivo,
      clabe: clabeEfectiva,
    )) {
      return CorregirEmpleadoDatosBancariosInvalidos();
    }

    final sueldoAdministrativoEfectivo =
        limpiarSueldoMensualAdministrativo ? null : (sueldoMensualAdministrativo ?? actual.sueldoMensualAdministrativo);
    if (!_validator.sueldoAdministrativoValido(sueldoAdministrativoEfectivo)) {
      return CorregirEmpleadoSueldoAdministrativoInvalido();
    }
    final bonoAdministrativoEfectivo =
        limpiarBonoMensualAdministrativo ? null : (bonoMensualAdministrativo ?? actual.bonoMensualAdministrativo);
    if (!_validator.bonoAdministrativoValido(bonoAdministrativoEfectivo)) {
      return CorregirEmpleadoBonoAdministrativoInvalido();
    }

    try {
      final cambios = EmpleadoCompanion(
        nombres: nombres == null ? const Value.absent() : Value(nombres.trim()),
        apellidoPaterno: apellidoPaterno == null ? const Value.absent() : Value(apellidoPaterno.trim()),
        apellidoMaterno: apellidoMaterno == null ? const Value.absent() : Value(_vacioANull(apellidoMaterno)),
        sexo: sexo == null ? const Value.absent() : Value(sexo.name),
        fechaNacimiento: fechaNacimiento == null ? const Value.absent() : Value(fechaNacimiento),
        curp: curp == null ? const Value.absent() : Value(curp.trim().toUpperCase()),
        rfc: rfc == null ? const Value.absent() : Value(rfc.trim().toUpperCase()),
        codigoPostalFiscal: limpiarCodigoPostalFiscal
            ? const Value(null)
            : (codigoPostalFiscal == null ? const Value.absent() : Value(_vacioANull(codigoPostalFiscal))),
        nss: nss == null ? const Value.absent() : Value(nss.trim()),
        estadoCivil: estadoCivil == null ? const Value.absent() : Value(estadoCivil.name),
        nacionalidad: nacionalidad == null ? const Value.absent() : Value(nacionalidad),
        telefono: telefono == null ? const Value.absent() : Value(_vacioANull(telefono)),
        correoElectronico: correoElectronico == null ? const Value.absent() : Value(_vacioANull(correoElectronico)),
        contactoEmergenciaNombre:
            contactoEmergenciaNombre == null ? const Value.absent() : Value(_vacioANull(contactoEmergenciaNombre)),
        telefonoEmergencia: telefonoEmergencia == null ? const Value.absent() : Value(_vacioANull(telefonoEmergencia)),
        parentescoEmergencia:
            parentescoEmergencia == null ? const Value.absent() : Value(_vacioANull(parentescoEmergencia)),
        bancoId: limpiarBanco ? const Value(null) : (bancoId == null ? const Value.absent() : Value(bancoId)),
        numeroCuentaTarjeta: limpiarNumeroCuentaTarjeta
            ? const Value(null)
            : (numeroCuentaTarjeta == null ? const Value.absent() : Value(_vacioANull(numeroCuentaTarjeta))),
        clabe: limpiarClabe ? const Value(null) : (clabe == null ? const Value.absent() : Value(_vacioANull(clabe))),
        fechaIngreso: fechaIngreso == null ? const Value.absent() : Value(fechaIngreso),
        puestoId: limpiarPuesto ? const Value(null) : (puestoId == null ? const Value.absent() : Value(puestoId)),
        empresaId: limpiarEmpresa ? const Value(null) : (empresaId == null ? const Value.absent() : Value(empresaId)),
        sucursalId:
            limpiarSucursal ? const Value(null) : (sucursalId == null ? const Value.absent() : Value(sucursalId)),
        sueldoMensualAdministrativo: limpiarSueldoMensualAdministrativo
            ? const Value(null)
            : (sueldoMensualAdministrativo == null ? const Value.absent() : Value(sueldoMensualAdministrativo)),
        bonoMensualAdministrativo: limpiarBonoMensualAdministrativo
            ? const Value(null)
            : (bonoMensualAdministrativo == null ? const Value.absent() : Value(bonoMensualAdministrativo)),
        observaciones: observaciones == null ? const Value.absent() : Value(_vacioANull(observaciones)),
        nivelEstudios: nivelEstudios == null ? const Value.absent() : Value(nivelEstudios.name),
        observacionesEscolaridad:
            observacionesEscolaridad == null ? const Value.absent() : Value(_vacioANull(observacionesEscolaridad)),
        aniosExperienciaSeguridad:
            aniosExperienciaSeguridad == null ? const Value.absent() : Value(aniosExperienciaSeguridad),
        mesesExperienciaAdicionales:
            mesesExperienciaAdicionales == null ? const Value.absent() : Value(mesesExperienciaAdicionales),
        ultimoPuestoDesempenado:
            ultimoPuestoDesempenado == null ? const Value.absent() : Value(_vacioANull(ultimoPuestoDesempenado)),
        resumenExperiencia: resumenExperiencia == null ? const Value.absent() : Value(_vacioANull(resumenExperiencia)),
        observacionesExperiencia: observacionesExperiencia == null
            ? const Value.absent()
            : Value(_vacioANull(observacionesExperiencia)),
      );

      final actualizado =
          await _repository.corregir(empleadoId: empleadoId, cambios: cambios, motivo: motivo, actor: actor);
      return CorregirEmpleadoExitoso(actualizado);
    } catch (e) {
      return CorregirEmpleadoErrorInesperado(e.toString());
    }
  }
}
