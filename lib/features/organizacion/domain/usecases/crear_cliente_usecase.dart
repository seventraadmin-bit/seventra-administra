import 'package:drift/drift.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/core/validation/rfc_validator.dart';

import '../repositories/cliente_repository.dart';

/// Prospectos pueden no tener RFC todavía — solo se valida/normaliza
/// cuando sí se proporciona uno.
class CrearClienteUseCase {
  CrearClienteUseCase(this._repository, this._generarCodigo);

  final ClienteRepository _repository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<Result<ClienteData>> ejecutar({
    required String razonSocial,
    String? nombreComercial,
    String? rfc,
    String? industriaId,
    String? observaciones,
  }) async {
    String? rfcNormalizado;
    if (rfc != null) {
      rfcNormalizado = RfcValidator.normalizar(rfc);
      if (!RfcValidator.esFormatoValido(rfcNormalizado)) {
        return Result.failure(ValidationFailure('El RFC "$rfc" no tiene un formato válido.'));
      }
      if (await _repository.existeRfc(rfcNormalizado)) {
        return Result.failure(ValidationFailure('Ya existe un cliente con el RFC $rfcNormalizado.'));
      }
    }

    final codigoResult = await _generarCodigo.ejecutar('cliente');
    final String codigo;
    switch (codigoResult) {
      case Ok<String>(value: final v):
        codigo = v;
      case Err<String>(failure: final f):
        return Result.failure(f);
    }

    final cliente = await _repository.crear(
      ClienteCompanion.insert(
        codigo: codigo,
        razonSocial: razonSocial,
        nombreComercial: Value(nombreComercial),
        rfc: Value(rfcNormalizado),
        industriaId: Value(industriaId),
        observaciones: Value(observaciones),
      ),
    );
    return Result.ok(cliente);
  }
}
