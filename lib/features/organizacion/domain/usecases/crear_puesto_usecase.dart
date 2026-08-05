import 'package:drift/drift.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/result.dart';

import '../repositories/puesto_repository.dart';
import 'guardar_puesto_resultado.dart';
import 'puesto_validator.dart';

/// Valida con `PuestoValidator` (nombre, Área existente y activa, tipo,
/// nivel jerárquico 1–10 — exactamente las mismas reglas que
/// `ActualizarPuestoUseCase`, nunca duplicadas) y solo entonces solicita
/// el código visible y persiste.
class CrearPuestoUseCase {
  CrearPuestoUseCase(this._repository, this._generarCodigo, this._validator);

  final PuestoRepository _repository;
  final GenerarCodigoUseCase _generarCodigo;
  final PuestoValidator _validator;

  Future<GuardarPuestoResultado> ejecutar(PuestoBorrador borrador) async {
    final validacion = await _validator.validar(borrador);
    if (validacion.errores.isNotEmpty) {
      return GuardarPuestoErroresValidacion(validacion.errores);
    }
    final validado = validacion.resultado!;

    final codigoResult = await _generarCodigo.ejecutar('puesto');
    final String codigo;
    switch (codigoResult) {
      case Ok<String>(value: final v):
        codigo = v;
      case Err<String>(failure: final f):
        return GuardarPuestoErrorInesperado(f.message);
    }

    try {
      final puesto = await _repository.crear(
        PuestoCompanion.insert(
          codigo: codigo,
          nombre: validado.nombre,
          areaId: validado.areaId,
          tipo: validado.tipo.name,
          nivelJerarquico: validado.nivelJerarquico,
          descripcion: Value(validado.descripcion),
        ),
      );
      return GuardarPuestoExitoso(puesto);
    } catch (e) {
      return GuardarPuestoErrorInesperado(e.toString());
    }
  }
}
