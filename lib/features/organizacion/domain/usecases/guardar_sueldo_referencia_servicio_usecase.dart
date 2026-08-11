import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/servicio_repository.dart';
import 'servicio_validator.dart';

sealed class GuardarSueldoReferenciaServicioResultado {}

class GuardarSueldoReferenciaServicioExitoso extends GuardarSueldoReferenciaServicioResultado {
  GuardarSueldoReferenciaServicioExitoso(this.servicio);
  final ServicioData servicio;
}

class GuardarSueldoReferenciaServicioNoExiste extends GuardarSueldoReferenciaServicioResultado {}

class GuardarSueldoReferenciaServicioSueldoInvalido extends GuardarSueldoReferenciaServicioResultado {}

class GuardarSueldoReferenciaServicioBonoInvalido extends GuardarSueldoReferenciaServicioResultado {}

/// Reservado para la frontera de autorización (Etapa 11C) — nunca lo
/// produce el propio caso de uso.
class GuardarSueldoReferenciaServicioErrorInesperado extends GuardarSueldoReferenciaServicioResultado {
  GuardarSueldoReferenciaServicioErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Guarda el sueldo/bono mensual de referencia de un Servicio (Etapa
/// 6B) — se precargan al crear una `AsignacionServicio` nueva contra
/// este Servicio (`AsignarEmpleadoServicioUseCase`/
/// `CambiarServicioEmpleadoUseCase`/`CrearEmpleadoUseCase`). Cambiar
/// estos valores nunca modifica retroactivamente asignaciones ya
/// existentes — cada una conserva su propio historial de vigencias de
/// sueldo (`AsignacionServicioSueldoVigencia`).
class GuardarSueldoReferenciaServicioUseCase {
  GuardarSueldoReferenciaServicioUseCase(this._repository, this._validator);

  final ServicioRepository _repository;
  final ServicioValidator _validator;

  Future<GuardarSueldoReferenciaServicioResultado> ejecutar({
    required String servicioId,
    required int? sueldoMensualReferenciaPersonal,
    required int? bonoMensualReferenciaPersonal,
  }) async {
    final servicio = await _repository.obtenerPorId(servicioId);
    if (servicio == null) return GuardarSueldoReferenciaServicioNoExiste();

    if (!_validator.sueldoReferenciaValido(sueldoMensualReferenciaPersonal)) {
      return GuardarSueldoReferenciaServicioSueldoInvalido();
    }
    if (!_validator.bonoReferenciaValido(bonoMensualReferenciaPersonal)) {
      return GuardarSueldoReferenciaServicioBonoInvalido();
    }

    final actualizado = await _repository.guardarSueldoReferencia(
      servicioId: servicioId,
      sueldoMensualReferenciaPersonal: sueldoMensualReferenciaPersonal,
      bonoMensualReferenciaPersonal: bonoMensualReferenciaPersonal,
    );
    return GuardarSueldoReferenciaServicioExitoso(actualizado);
  }
}
