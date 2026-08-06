import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';

import '../repositories/configuracion_cobro_repository.dart';
import '../repositories/servicio_repository.dart';
import 'configuracion_cobro_errors.dart';
import 'configuracion_cobro_regla_evento_errors.dart';
import 'configuracion_cobro_regla_evento_validator.dart';
import 'configuracion_cobro_validator.dart';

sealed class CrearConfiguracionCobroResultado {}

class CrearConfiguracionCobroExitoso extends CrearConfiguracionCobroResultado {
  CrearConfiguracionCobroExitoso(this.configuracion, this.vigencia);
  final ConfiguracionCobroData configuracion;
  final ConfiguracionCobroVigenciaData vigencia;
}

class CrearConfiguracionCobroErroresValidacion extends CrearConfiguracionCobroResultado {
  CrearConfiguracionCobroErroresValidacion(this.errores, [this.erroresReglas = const []]);
  final List<ErrorConfiguracionCobro> errores;

  /// Errores de las reglas de evento (Etapa 4H.2) — lista separada
  /// porque cada error ya lleva su propio `TipoEventoCobro`, un campo
  /// que `ErrorConfiguracionCobro` no tiene.
  final List<ErrorReglaEvento> erroresReglas;
}

/// Mismo criterio que `CrearLineaComercialUseCase`: un Servicio
/// `terminado` no admite nueva Configuración de cobro.
class CrearConfiguracionCobroServicioNoDisponible extends CrearConfiguracionCobroResultado {}

/// El Servicio ya tiene una Configuración de cobro — 1:1, no se puede
/// crear una segunda (para cambiar condiciones, la Etapa 4H.2 aportará
/// "nueva vigencia").
class CrearConfiguracionCobroYaExiste extends CrearConfiguracionCobroResultado {}

class CrearConfiguracionCobroErrorInesperado extends CrearConfiguracionCobroResultado {
  CrearConfiguracionCobroErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Da de alta la Configuración de cobro de un Servicio con su primera
/// vigencia — nunca una vigencia "suelta" sin configuración, ni una
/// configuración sin al menos una vigencia (mismo principio que
/// `CrearLineaComercialUseCase`).
class CrearConfiguracionCobroUseCase {
  CrearConfiguracionCobroUseCase(this._repository, this._servicioRepository, this._validator, this._reglaValidator);

  final ConfiguracionCobroRepository _repository;
  final ServicioRepository _servicioRepository;
  final ConfiguracionCobroValidator _validator;
  final ConfiguracionCobroReglaEventoValidator _reglaValidator;

  Future<CrearConfiguracionCobroResultado> ejecutar({
    required String servicioId,
    required ConfiguracionCobroBorrador borrador,
    List<ReglaEventoBorrador> reglas = const [],
  }) async {
    final servicio = await _servicioRepository.obtenerPorId(servicioId);
    if (servicio != null && EstatusServicio.values.byName(servicio.estatus) == EstatusServicio.terminado) {
      return CrearConfiguracionCobroServicioNoDisponible();
    }

    final existente = await _repository.obtenerConfiguracion(servicioId);
    if (existente != null) {
      return CrearConfiguracionCobroYaExiste();
    }

    final validacion = await _validator.validar(servicioId: servicioId, borrador: borrador);
    final validacionReglas = _reglaValidator.validar(reglas);
    if (validacion.errores.isNotEmpty || validacionReglas.errores.isNotEmpty) {
      return CrearConfiguracionCobroErroresValidacion(validacion.errores, validacionReglas.errores);
    }

    try {
      final creado = await _repository.crearConfiguracion(
        servicioId: servicioId,
        datos: validacion.resultado!,
        reglas: validacionReglas.resultado,
      );
      return CrearConfiguracionCobroExitoso(creado.configuracion, creado.vigencia);
    } catch (e) {
      return CrearConfiguracionCobroErrorInesperado(e.toString());
    }
  }
}
