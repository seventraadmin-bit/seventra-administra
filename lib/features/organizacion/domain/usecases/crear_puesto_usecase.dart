import 'package:drift/drift.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart';

import '../repositories/puesto_repository.dart';

class CrearPuestoUseCase {
  CrearPuestoUseCase(this._repository, this._generarCodigo);

  final PuestoRepository _repository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<Result<PuestoData>> ejecutar({
    required String nombre,
    required String areaId,
    required TipoPuesto tipo,
    required int nivelJerarquico,
    String? descripcion,
  }) async {
    final codigoResult = await _generarCodigo.ejecutar('puesto');
    final String codigo;
    switch (codigoResult) {
      case Ok<String>(value: final v):
        codigo = v;
      case Err<String>(failure: final f):
        return Result.failure(f);
    }

    final puesto = await _repository.crear(
      PuestoCompanion.insert(
        codigo: codigo,
        nombre: nombre,
        areaId: areaId,
        tipo: tipo.name,
        nivelJerarquico: nivelJerarquico,
        descripcion: Value(descripcion),
      ),
    );
    return Result.ok(puesto);
  }
}
