import 'package:drift/drift.dart';
import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';

import '../repositories/cliente_repository.dart';
import '../shared/direccion_input.dart';
import 'cliente_expediente_data.dart';
import 'cliente_expediente_errors.dart';
import 'cliente_expediente_input.dart';

/// Resultado de [GuardarExpedienteClienteUseCase] — su propio tipo
/// sellado, mismo patrón que `GuardarExpedienteSucursalResultado`.
sealed class GuardarExpedienteClienteResultado {}

class GuardarExpedienteClienteExitoso extends GuardarExpedienteClienteResultado {
  GuardarExpedienteClienteExitoso(this.datos);
  final ClienteExpedienteData datos;
}

class GuardarExpedienteClienteErroresValidacion extends GuardarExpedienteClienteResultado {
  GuardarExpedienteClienteErroresValidacion(this.errores);
  final List<ErrorExpedienteCliente> errores;
}

/// Sin motivo no hay corrección: la bitácora quedaría sin el porqué.
class GuardarExpedienteClienteMotivoRequerido extends GuardarExpedienteClienteResultado {}

class GuardarExpedienteClienteErrorInesperado extends GuardarExpedienteClienteResultado {
  GuardarExpedienteClienteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Coordina el guardado de datos generales + dirección de referencia,
/// validando primero y persistiendo todo en una sola transacción
/// después (vía `ClienteRepository.guardarExpediente`). Contactos se
/// administran por separado (`AgregarContactoUseCase` y similares), no
/// como parte de este guardado — igual que el ciclo de vida de Puesto
/// es una acción independiente de su guardado de formulario.
class GuardarExpedienteClienteUseCase {
  GuardarExpedienteClienteUseCase(this._repository);

  final ClienteRepository _repository;

  /// [motivo] es obligatorio: corregir los datos comerciales de un
  /// Cliente es un cambio sensible y tiene que poder explicarse después.
  Future<GuardarExpedienteClienteResultado> ejecutar({
    required String clienteId,
    required ClienteExpedienteInput input,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) return GuardarExpedienteClienteMotivoRequerido();
    final errores = <ErrorExpedienteCliente>[];

    final nombreComercial = input.datosGenerales.nombreComercial.trim();
    if (nombreComercial.isEmpty) {
      errores.add(ErrorNombreComercialRequerido());
    }

    DireccionInput? direccionValidada;
    final borradorDireccion = input.direccionReferencia;
    if (borradorDireccion != null) {
      final r = DireccionValidator.validar(borradorDireccion);
      for (final e in r.errores) {
        errores.add(ErrorDireccionCliente(e));
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

    if (errores.isNotEmpty) {
      return GuardarExpedienteClienteErroresValidacion(errores);
    }

    final observacionesLimpias = input.datosGenerales.observaciones?.trim();

    try {
      final resultado = await _repository.guardarExpediente(
        clienteId: clienteId,
        datosGenerales: ClienteCompanion(
          nombreComercial: Value(nombreComercial),
          observaciones: Value(
            (observacionesLimpias == null || observacionesLimpias.isEmpty) ? null : observacionesLimpias,
          ),
        ),
        direccionReferencia: direccionValidada,
        motivo: motivo.trim(),
        actorUsuarioId: actorUsuarioId,
      );

      return GuardarExpedienteClienteExitoso(
        ClienteExpedienteData(cliente: resultado.cliente, direccionReferencia: resultado.direccionReferencia),
      );
    } catch (e) {
      return GuardarExpedienteClienteErrorInesperado(e.toString());
    }
  }
}
