import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/result.dart';

import '../repositories/sucursal_repository.dart';

/// Crea una Sucursal, su nodo raíz de Ubicación y el Almacén General —
/// solicita los tres códigos visibles y ordena la operación;
/// `SucursalRepository` es quien la ejecuta como una sola transacción.
class CrearSucursalUseCase {
  CrearSucursalUseCase(this._repository, this._generarCodigo);

  final SucursalRepository _repository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<Result<SucursalData>> ejecutar({
    required String nombre,
    required String tipoSucursalId,
  }) async {
    final codigoSucursal = await _generarCodigo.ejecutar('sucursal');
    final String cSucursal;
    switch (codigoSucursal) {
      case Ok<String>(value: final v):
        cSucursal = v;
      case Err<String>(failure: final f):
        return Result.failure(f);
    }

    final codigoRaiz = await _generarCodigo.ejecutar('ubicacion');
    final String cRaiz;
    switch (codigoRaiz) {
      case Ok<String>(value: final v):
        cRaiz = v;
      case Err<String>(failure: final f):
        return Result.failure(f);
    }

    final codigoAlmacen = await _generarCodigo.ejecutar('ubicacion');
    final String cAlmacen;
    switch (codigoAlmacen) {
      case Ok<String>(value: final v):
        cAlmacen = v;
      case Err<String>(failure: final f):
        return Result.failure(f);
    }

    final sucursal = await _repository.crear(
      codigoSucursal: cSucursal,
      nombre: nombre,
      tipoSucursalId: tipoSucursalId,
      codigoUbicacionRaiz: cRaiz,
      codigoAlmacenGeneral: cAlmacen,
    );
    return Result.ok(sucursal);
  }
}
