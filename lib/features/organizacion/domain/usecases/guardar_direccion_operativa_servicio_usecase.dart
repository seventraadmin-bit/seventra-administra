import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';

import '../repositories/servicio_repository.dart';
import '../shared/direccion_input.dart';

/// Resultado de [GuardarDireccionOperativaServicioUseCase] — mismo
/// patrón que `GuardarDomicilioFiscalResultado`, sin variante
/// "Archivada": Servicio no tiene todavía un estado de solo-lectura por
/// archivado (Etapa 4F.1, punto 7 — la acción de archivar Servicio
/// queda para cuando exista una regla clara al respecto).
sealed class GuardarDireccionOperativaServicioResultado {}

class GuardarDireccionOperativaServicioExitoso extends GuardarDireccionOperativaServicioResultado {
  GuardarDireccionOperativaServicioExitoso(this.direccion);
  final DireccionData? direccion;
}

class GuardarDireccionOperativaServicioErroresValidacion extends GuardarDireccionOperativaServicioResultado {
  GuardarDireccionOperativaServicioErroresValidacion(this.errores);
  final List<ErrorCampoDireccion> errores;
}

class GuardarDireccionOperativaServicioErrorInesperado extends GuardarDireccionOperativaServicioResultado {
  GuardarDireccionOperativaServicioErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Captura/edita/limpia la Dirección operativa de un Servicio ya
/// existente. Un domicilio completamente vacío nunca se persiste
/// (`DireccionBorrador.estaCompletamenteVacia` = "sin dirección"); uno
/// parcialmente incompleto es rechazado por `DireccionValidator`; si
/// había una Dirección y se vacía por completo, el repositorio la
/// archiva — nunca un `hard delete`. El repositorio garantiza además,
/// vía `UNIQUE` real en `servicio_id`, que nunca exista más de una
/// Dirección operativa activa por Servicio (mismo patrón de upsert que
/// `GuardarDomicilioFiscalUseCase`).
class GuardarDireccionOperativaServicioUseCase {
  GuardarDireccionOperativaServicioUseCase(this._repository);

  final ServicioRepository _repository;

  Future<GuardarDireccionOperativaServicioResultado> ejecutar({
    required String servicioId,
    required DireccionBorrador? domicilio,
  }) async {
    DireccionInput? validado;
    if (domicilio != null) {
      final r = DireccionValidator.validar(domicilio);
      if (r.errores.isNotEmpty) {
        return GuardarDireccionOperativaServicioErroresValidacion(r.errores);
      }
      final d = r.resultado;
      if (d != null) {
        validado = DireccionInput(
          calle: d.calle,
          numeroExterior: d.numeroExterior,
          numeroInterior: d.numeroInterior,
          colonia: d.colonia,
          municipioAlcaldia: d.municipioAlcaldia,
          ciudadLocalidad: d.ciudadLocalidad,
          estado: d.estado,
          codigoPostal: d.codigoPostal,
          pais: d.pais,
          referencias: d.referencias,
        );
      }
    }

    try {
      final resultado = await _repository.guardarDireccionOperativa(servicioId, validado);
      return GuardarDireccionOperativaServicioExitoso(resultado);
    } catch (e) {
      return GuardarDireccionOperativaServicioErrorInesperado(e.toString());
    }
  }
}
