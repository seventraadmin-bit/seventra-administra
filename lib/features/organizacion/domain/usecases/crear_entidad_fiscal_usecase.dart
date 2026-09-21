import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/result.dart';

import '../repositories/entidad_fiscal_repository.dart';
import 'entidad_fiscal_validator.dart';
import 'guardar_entidad_fiscal_resultado.dart';

/// Alta de Entidad fiscal — solo razón social + RFC. El domicilio
/// fiscal es siempre una acción separada
/// (`GuardarDomicilioFiscalUseCase`), nunca parte de este formulario:
/// así "el domicilio puede quedar pendiente durante el alta inicial" es
/// literal, y editar razón social/RFC después nunca arriesga borrar un
/// domicilio ya capturado por no haberlo vuelto a incluir en el envío.
class CrearEntidadFiscalUseCase {
  CrearEntidadFiscalUseCase(this._repository, this._generarCodigo, this._validator);

  final EntidadFiscalRepository _repository;
  final GenerarCodigoUseCase _generarCodigo;
  final EntidadFiscalValidator _validator;

  Future<GuardarEntidadFiscalResultado> ejecutar({
    required String clienteId,
    required EntidadFiscalBorrador borrador,
    String? actorUsuarioId,
  }) async {
    final validacion = await _validator.validar(clienteId: clienteId, borrador: borrador);
    if (validacion.errores.isNotEmpty) {
      return GuardarEntidadFiscalErroresValidacion(
        [for (final e in validacion.errores) ErrorCampoEntidadFiscalGeneral(e)],
      );
    }
    final validado = validacion.resultado!;

    final codigoResult = await _generarCodigo.ejecutar('entidad_fiscal');
    final String codigo;
    switch (codigoResult) {
      case Ok<String>(value: final v):
        codigo = v;
      case Err<String>(failure: final f):
        return GuardarEntidadFiscalErrorInesperado(f.message);
    }

    try {
      final entidad = await _repository.crear(
        EntidadFiscalCompanion.insert(
          codigo: codigo,
          clienteId: clienteId,
          razonSocial: validado.razonSocial,
          rfc: validado.rfc,
        ),
        actorUsuarioId: actorUsuarioId,
      );
      return GuardarEntidadFiscalExitoso(entidad);
    } catch (e) {
      return GuardarEntidadFiscalErrorInesperado(e.toString());
    }
  }
}
