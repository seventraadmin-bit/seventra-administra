import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/servicio_repository.dart';
import 'guardar_servicio_resultado.dart';
import 'servicio_validator.dart';

/// Comparte exactamente las mismas reglas que `CrearServicioUseCase` vía
/// `ServicioValidator` — mismo patrón que `ActualizarPuestoUseCase`/
/// `ActualizarEntidadFiscalUseCase`. Nunca acepta un `clienteId` nuevo:
/// la relación con el Cliente es inmutable, así que se relee del
/// registro existente, nunca del formulario. Nunca toca `fechaTermino`
/// ni `estatus` — esos viven en `CambiarEstatusServicioUseCase`.
class ActualizarServicioUseCase {
  ActualizarServicioUseCase(this._repository, this._validator);

  final ServicioRepository _repository;
  final ServicioValidator _validator;

  Future<GuardarServicioResultado> ejecutar({
    required String id,
    required ServicioBorrador borrador,
  }) async {
    final existente = await _repository.obtenerPorId(id);
    if (existente == null) {
      return GuardarServicioErrorInesperado('Servicio no encontrado: $id');
    }

    final validacion = await _validator.validar(clienteId: existente.clienteId, borrador: borrador);
    if (validacion.errores.isNotEmpty) {
      return GuardarServicioErroresValidacion(validacion.errores);
    }
    final validado = validacion.resultado!;

    try {
      final actualizado = await _repository.actualizar(
        id: id,
        cambios: ServicioCompanion(
          nombre: Value(validado.nombre),
          tipoServicioId: Value(validado.tipoServicioId),
          fechaInicio: Value(validado.fechaInicio),
          observaciones: Value(validado.observaciones),
          referenciaComercial: Value(validado.referenciaComercial),
          referenciaContractual: Value(validado.referenciaContractual),
        ),
      );
      return GuardarServicioExitoso(actualizado);
    } catch (e) {
      return GuardarServicioErrorInesperado(e.toString());
    }
  }
}
