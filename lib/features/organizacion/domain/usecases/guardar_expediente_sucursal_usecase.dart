import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';

import '../repositories/sucursal_repository.dart';
import '../shared/direccion_input.dart';
import '../shared/horario_input.dart';
import 'sucursal_expediente_data.dart';
import 'sucursal_expediente_errors.dart';
import 'sucursal_expediente_input.dart';

/// Resultado de [GuardarExpedienteSucursalUseCase] — su propio tipo
/// sellado, mismo patrón que `GuardarExpedienteResultado` de Empresa.
sealed class GuardarExpedienteSucursalResultado {}

class GuardarExpedienteSucursalExitoso extends GuardarExpedienteSucursalResultado {
  GuardarExpedienteSucursalExitoso(this.datos);
  final SucursalExpedienteData datos;
}

class GuardarExpedienteSucursalErroresValidacion extends GuardarExpedienteSucursalResultado {
  GuardarExpedienteSucursalErroresValidacion(this.errores);
  final List<ErrorExpedienteSucursal> errores;
}

class GuardarExpedienteSucursalErrorInesperado extends GuardarExpedienteSucursalResultado {
  GuardarExpedienteSucursalErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Coordina el guardado completo del expediente de Sucursal: datos
/// generales, dirección principal y horario semanal, validando primero y
/// persistiendo todo en una sola transacción después (vía
/// `SucursalRepository.guardarExpediente`). Reúne *todos* los errores de
/// las tres secciones antes de fallar, igual que Empresa en 4B.
class GuardarExpedienteSucursalUseCase {
  GuardarExpedienteSucursalUseCase(this._repository);

  final SucursalRepository _repository;

  Future<GuardarExpedienteSucursalResultado> ejecutar({
    required String sucursalId,
    required SucursalExpedienteInput input,
  }) async {
    final errores = <ErrorExpedienteSucursal>[];

    if (input.datosGenerales.tipoSucursalId.trim().isEmpty) {
      errores.add(ErrorTipoSucursalRequerido());
    }

    DireccionInput? direccionValidada;
    if (input.direccionPrincipal != null) {
      final r = DireccionValidator.validar(input.direccionPrincipal!);
      for (final e in r.errores) {
        errores.add(ErrorDireccionSucursal(e));
      }
      final validada = r.resultado;
      if (validada != null) {
        direccionValidada = DireccionInput(
          calle: validada.calle,
          numeroExterior: validada.numeroExterior,
          numeroInterior: validada.numeroInterior,
          colonia: validada.colonia,
          municipioAlcaldia: validada.municipioAlcaldia,
          ciudadLocalidad: validada.ciudadLocalidad,
          estado: validada.estado,
          codigoPostal: validada.codigoPostal,
          pais: validada.pais,
          referencias: validada.referencias,
        );
      }
    }

    HorarioSemanalInput? horarioValidado;
    final borradorHorario = input.horario;
    if (borradorHorario != null && !borradorHorario.estaCompletamenteVacio) {
      horarioValidado = _validarHorario(borradorHorario, errores);
    }

    if (errores.isNotEmpty) {
      return GuardarExpedienteSucursalErroresValidacion(errores);
    }

    try {
      final resultado = await _repository.guardarExpediente(
        sucursalId: sucursalId,
        datosGenerales: SucursalCompanion(
          nombre: Value(input.datosGenerales.nombre.trim()),
          tipoSucursalId: Value(input.datosGenerales.tipoSucursalId),
        ),
        direccionPrincipal: direccionValidada,
        horario: horarioValidado,
      );

      return GuardarExpedienteSucursalExitoso(
        SucursalExpedienteData(
          sucursal: resultado.sucursal,
          direccionPrincipal: resultado.direccionPrincipal,
          horario: resultado.horario,
        ),
      );
    } catch (e) {
      return GuardarExpedienteSucursalErrorInesperado(e.toString());
    }
  }

  /// `null` cuando algún día abierto reporta un error — el llamador ya
  /// tiene esos errores en la lista compartida y no debe persistir nada.
  /// Delega la validación día por día a `validarHorarioSemanal`
  /// (compartida con el horario personalizado de línea comercial, Etapa
  /// 15) y solo adapta cada `HorarioErrorDia` a `ErrorHorarioSucursal`.
  HorarioSemanalInput? _validarHorario(
    HorarioSemanalBorrador borrador,
    List<ErrorExpedienteSucursal> errores,
  ) {
    final validacion = validarHorarioSemanal(borrador);
    for (final error in validacion.errores) {
      errores.add(ErrorHorarioSucursal(dia: error.dia, codigo: error.codigo));
    }
    return validacion.resultado;
  }
}
