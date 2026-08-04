import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/core/validation/rfc_validator.dart';

import '../repositories/empresa_repository.dart';

/// Actualiza los datos generales de la Empresa activa.
///
/// Devuelve la Empresa ya actualizada (no `void`) — el llamador nunca
/// necesita una segunda consulta solo para ver el resultado.
class ActualizarEmpresaUseCase {
  ActualizarEmpresaUseCase(this._repository);

  final EmpresaRepository _repository;

  Future<Result<EmpresaData>> ejecutar({
    String? razonSocial,
    String? nombreComercial,
    String? rfc,
    String? representanteLegal,
    String? eslogan,
  }) async {
    String? rfcNormalizado;
    if (rfc != null) {
      rfcNormalizado = RfcValidator.normalizar(rfc);
      if (!RfcValidator.esFormatoValido(rfcNormalizado)) {
        return Result.failure(ValidationFailure('El RFC "$rfc" no tiene un formato válido.'));
      }
    }

    try {
      await _repository.actualizarDatosGenerales(
        EmpresaCompanion(
          razonSocial: razonSocial == null ? const Value.absent() : Value(razonSocial),
          nombreComercial: nombreComercial == null ? const Value.absent() : Value(nombreComercial),
          rfc: rfcNormalizado == null ? const Value.absent() : Value(rfcNormalizado),
          representanteLegal:
              representanteLegal == null ? const Value.absent() : Value(representanteLegal),
          eslogan: eslogan == null ? const Value.absent() : Value(eslogan),
        ),
      );
      return Result.ok(await _repository.obtenerActiva());
    } on StateError catch (e) {
      return Result.failure(NotFoundFailure(e.message));
    }
  }
}
