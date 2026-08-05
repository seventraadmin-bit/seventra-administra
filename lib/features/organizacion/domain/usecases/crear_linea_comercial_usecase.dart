import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';

import '../repositories/servicio_comercial_repository.dart';
import '../repositories/servicio_repository.dart';
import 'linea_comercial_errors.dart';
import 'linea_comercial_validator.dart';

sealed class CrearLineaComercialResultado {}

class CrearLineaComercialExitoso extends CrearLineaComercialResultado {
  CrearLineaComercialExitoso(this.linea, this.vigencia);
  final ServicioLineaComercialData linea;
  final ServicioLineaComercialVigenciaData vigencia;
}

class CrearLineaComercialErroresValidacion extends CrearLineaComercialResultado {
  CrearLineaComercialErroresValidacion(this.errores);
  final List<ErrorLineaComercial> errores;
}

/// El Servicio ya no admite nuevas condiciones comerciales — mismo
/// criterio que el resto del expediente: un Servicio `terminado` es de
/// solo lectura.
class CrearLineaComercialServicioNoDisponible extends CrearLineaComercialResultado {}

class CrearLineaComercialErrorInesperado extends CrearLineaComercialResultado {
  CrearLineaComercialErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Da de alta una línea comercial nueva con su primera vigencia — nunca
/// una vigencia "sola" sin línea, ni una línea sin al menos una
/// vigencia.
class CrearLineaComercialUseCase {
  CrearLineaComercialUseCase(this._repository, this._servicioRepository, this._validator);

  final ServicioComercialRepository _repository;
  final ServicioRepository _servicioRepository;
  final LineaComercialValidator _validator;

  Future<CrearLineaComercialResultado> ejecutar({
    required String servicioId,
    required LineaComercialBorrador borrador,
  }) async {
    final servicio = await _servicioRepository.obtenerPorId(servicioId);
    if (servicio != null && EstatusServicio.values.byName(servicio.estatus) == EstatusServicio.terminado) {
      return CrearLineaComercialServicioNoDisponible();
    }

    final validacion = await _validator.validar(servicioId: servicioId, borrador: borrador);
    if (validacion.errores.isNotEmpty) {
      return CrearLineaComercialErroresValidacion(validacion.errores);
    }

    try {
      final creado = await _repository.crearLinea(servicioId: servicioId, datos: validacion.resultado!);
      return CrearLineaComercialExitoso(creado.linea, creado.vigencia);
    } catch (e) {
      return CrearLineaComercialErrorInesperado(e.toString());
    }
  }
}
