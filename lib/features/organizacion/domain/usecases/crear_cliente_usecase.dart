import 'package:drift/drift.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';

import '../repositories/cliente_repository.dart';

/// Alta mínima de Cliente comercial — solo nombre comercial +
/// observaciones opcionales. Nace siempre con estatus `prospecto`;
/// dirección de referencia, contactos y (en la Etapa 4E.2) Entidades
/// fiscales se capturan después, en el expediente.
class CrearClienteUseCase {
  CrearClienteUseCase(this._repository, this._generarCodigo);

  final ClienteRepository _repository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<Result<ClienteData>> ejecutar({required String nombreComercial, String? observaciones}) async {
    final nombreLimpio = nombreComercial.trim();
    if (nombreLimpio.isEmpty) {
      return const Result.failure(ValidationFailure('El nombre comercial es obligatorio.'));
    }

    final codigoResult = await _generarCodigo.ejecutar('cliente');
    final String codigo;
    switch (codigoResult) {
      case Ok<String>(value: final v):
        codigo = v;
      case Err<String>(failure: final f):
        return Result.failure(f);
    }

    final observacionesLimpias = observaciones?.trim();

    final cliente = await _repository.crear(
      ClienteCompanion.insert(
        codigo: codigo,
        nombreComercial: nombreLimpio,
        observaciones: Value(
          (observacionesLimpias == null || observacionesLimpias.isEmpty) ? null : observacionesLimpias,
        ),
      ),
    );
    return Result.ok(cliente);
  }
}
