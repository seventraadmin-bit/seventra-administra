import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';

import '../repositories/entidad_fiscal_repository.dart';
import '../shared/direccion_input.dart';

/// Resultado de [GuardarDomicilioFiscalUseCase] — propio, porque el
/// domicilio fiscal se administra completamente aparte de razón
/// social/RFC (ver `CrearEntidadFiscalUseCase`).
sealed class GuardarDomicilioFiscalResultado {}

class GuardarDomicilioFiscalExitoso extends GuardarDomicilioFiscalResultado {
  GuardarDomicilioFiscalExitoso(this.domicilio);
  final DireccionData? domicilio;
}

class GuardarDomicilioFiscalErroresValidacion extends GuardarDomicilioFiscalResultado {
  GuardarDomicilioFiscalErroresValidacion(this.errores);
  final List<ErrorCampoDireccion> errores;
}

/// Solo posible si la Entidad fiscal dueña está archivada — de solo
/// consulta hasta reactivarse, mismo criterio que
/// `ActualizarEntidadFiscalUseCase`.
class GuardarDomicilioFiscalArchivada extends GuardarDomicilioFiscalResultado {}

class GuardarDomicilioFiscalErrorInesperado extends GuardarDomicilioFiscalResultado {
  GuardarDomicilioFiscalErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Captura/edita/limpia el domicilio fiscal de una Entidad fiscal ya
/// existente. Un domicilio vacío nunca se persiste (`DireccionBorrador`
/// completamente vacío = "sin domicilio"); uno parcialmente incompleto
/// es rechazado por `DireccionValidator`; si había uno y se vacía por
/// completo, el repositorio lo archiva — nunca un `hard delete`.
class GuardarDomicilioFiscalUseCase {
  GuardarDomicilioFiscalUseCase(this._repository);

  final EntidadFiscalRepository _repository;

  Future<GuardarDomicilioFiscalResultado> ejecutar({
    required String entidadFiscalId,
    required DireccionBorrador? domicilio,
  }) async {
    final entidad = await _repository.obtenerPorId(entidadFiscalId);
    if (entidad == null) {
      return GuardarDomicilioFiscalErrorInesperado('Entidad fiscal no encontrada: $entidadFiscalId');
    }
    if (entidad.cicloVidaRegistro != CicloVidaRegistro.activo.name) {
      return GuardarDomicilioFiscalArchivada();
    }

    DireccionInput? validado;
    if (domicilio != null) {
      final r = DireccionValidator.validar(domicilio);
      if (r.errores.isNotEmpty) {
        return GuardarDomicilioFiscalErroresValidacion(r.errores);
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
      final resultado = await _repository.guardarDomicilioFiscal(entidadFiscalId, validado);
      return GuardarDomicilioFiscalExitoso(resultado);
    } catch (e) {
      return GuardarDomicilioFiscalErrorInesperado(e.toString());
    }
  }
}
