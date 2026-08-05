import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/error/result.dart';

import '../repositories/area_repository.dart';
import 'guardar_area_resultado.dart';

class CrearAreaUseCase {
  CrearAreaUseCase(this._repository, this._generarCodigo);

  final AreaRepository _repository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<GuardarAreaResultado> ejecutar({required String nombre, String? descripcion}) async {
    final nombreLimpio = nombre.trim();
    if (nombreLimpio.isEmpty) {
      return GuardarAreaNombreRequerido();
    }

    final codigoResult = await _generarCodigo.ejecutar('area');
    final String codigo;
    switch (codigoResult) {
      case Ok<String>(value: final v):
        codigo = v;
      case Err<String>(failure: final f):
        return GuardarAreaErrorInesperado(f.message);
    }

    try {
      final descripcionLimpia = descripcion?.trim();
      final area = await _repository.crear(
        codigo: codigo,
        nombre: nombreLimpio,
        descripcion: (descripcionLimpia == null || descripcionLimpia.isEmpty) ? null : descripcionLimpia,
      );
      return GuardarAreaExitoso(area);
    } catch (e) {
      return GuardarAreaErrorInesperado(e.toString());
    }
  }
}
