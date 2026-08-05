import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/puesto_repository.dart';
import 'guardar_puesto_resultado.dart';
import 'puesto_validator.dart';

/// Comparte exactamente las mismas reglas que `CrearPuestoUseCase` vía
/// `PuestoValidator` — incluida la validación de que el Área destino
/// exista y esté activa cuando se cambia de Área al editar. La FK de
/// base de datos sigue protegiendo que el Área exista; no protege que
/// esté activa, así que esa parte depende enteramente de este caso de
/// uso, nunca solo de que `RisegSelect` muestre opciones activas.
class ActualizarPuestoUseCase {
  ActualizarPuestoUseCase(this._repository, this._validator);

  final PuestoRepository _repository;
  final PuestoValidator _validator;

  Future<GuardarPuestoResultado> ejecutar({required String id, required PuestoBorrador borrador}) async {
    final validacion = await _validator.validar(borrador);
    if (validacion.errores.isNotEmpty) {
      return GuardarPuestoErroresValidacion(validacion.errores);
    }
    final validado = validacion.resultado!;

    try {
      final puesto = await _repository.actualizar(
        id: id,
        cambios: PuestoCompanion(
          nombre: Value(validado.nombre),
          areaId: Value(validado.areaId),
          tipo: Value(validado.tipo.name),
          nivelJerarquico: Value(validado.nivelJerarquico),
          descripcion: Value(validado.descripcion),
        ),
      );
      return GuardarPuestoExitoso(puesto);
    } catch (e) {
      return GuardarPuestoErrorInesperado(e.toString());
    }
  }
}
