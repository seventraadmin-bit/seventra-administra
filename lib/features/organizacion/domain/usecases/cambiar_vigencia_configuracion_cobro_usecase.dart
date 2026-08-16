import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';

import '../repositories/configuracion_cobro_repository.dart';
import '../repositories/servicio_repository.dart';
import 'configuracion_cobro_errors.dart';
import 'configuracion_cobro_etapa_errors.dart';
import 'configuracion_cobro_etapa_validator.dart';
import 'configuracion_cobro_validator.dart';

sealed class CambiarVigenciaConfiguracionCobroResultado {}

class CambiarVigenciaConfiguracionCobroExitoso extends CambiarVigenciaConfiguracionCobroResultado {
  CambiarVigenciaConfiguracionCobroExitoso(this.vigencia);
  final ConfiguracionCobroVigenciaData vigencia;
}

class CambiarVigenciaConfiguracionCobroErroresValidacion extends CambiarVigenciaConfiguracionCobroResultado {
  CambiarVigenciaConfiguracionCobroErroresValidacion(this.errores, [this.erroresEtapas = const []]);
  final List<ErrorConfiguracionCobro> errores;
  final List<ErrorEtapaCobro> erroresEtapas;
}

class CambiarVigenciaConfiguracionCobroNoExiste extends CambiarVigenciaConfiguracionCobroResultado {}

/// Mismo criterio que `CrearConfiguracionCobroUseCase`: un Servicio
/// `terminado` no admite una nueva condición de cobro. Cerrar/cancelar/
/// actualizar observaciones NO pasan por este bloqueo — solo registrar
/// una condición nueva.
class CambiarVigenciaConfiguracionCobroServicioNoDisponible extends CambiarVigenciaConfiguracionCobroResultado {}

class CambiarVigenciaConfiguracionCobroErrorInesperado extends CambiarVigenciaConfiguracionCobroResultado {
  CambiarVigenciaConfiguracionCobroErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra una nueva vigencia sobre una Configuración de cobro ya
/// existente — mismo algoritmo único de predecesora/sucesora que
/// `CambiarVigenciaLineaComercialUseCase` (Etapa 4G.2), aplicado aquí
/// (Resolución A de la Etapa 4H.2). Las reglas temporales forman parte
/// de la vigencia: cualquier cambio a ellas exige registrar una nueva
/// vigencia completa, nunca editarlas in place.
class CambiarVigenciaConfiguracionCobroUseCase {
  CambiarVigenciaConfiguracionCobroUseCase(
    this._repository,
    this._servicioRepository,
    this._validator,
    this._etapaValidator,
  );

  final ConfiguracionCobroRepository _repository;
  final ServicioRepository _servicioRepository;
  final ConfiguracionCobroValidator _validator;
  final ConfiguracionCobroEtapaValidator _etapaValidator;

  Future<CambiarVigenciaConfiguracionCobroResultado> ejecutar({
    required String configuracionCobroId,
    required ConfiguracionCobroBorrador borrador,
    List<EtapaCobroBorrador> etapas = const [],
  }) async {
    final configuracion = await _repository.obtenerConfiguracionPorId(configuracionCobroId);
    if (configuracion == null) {
      return CambiarVigenciaConfiguracionCobroNoExiste();
    }

    final servicio = await _servicioRepository.obtenerPorId(configuracion.servicioId);
    if (servicio != null && EstatusServicio.values.byName(servicio.estatus) == EstatusServicio.terminado) {
      return CambiarVigenciaConfiguracionCobroServicioNoDisponible();
    }

    final historial = await _repository.listarHistorial(configuracionCobroId);
    final vigenciasActivas = historial.where((v) => v.cicloVidaRegistro == CicloVidaRegistro.activo.name).toList();

    final validacion = await _validator.validar(
      servicioId: configuracion.servicioId,
      borrador: borrador,
      vigenciasExistentes: vigenciasActivas,
    );
    final validacionEtapas = _etapaValidator.validar(etapas);
    if (validacion.errores.isNotEmpty || validacionEtapas.errores.isNotEmpty) {
      return CambiarVigenciaConfiguracionCobroErroresValidacion(validacion.errores, validacionEtapas.errores);
    }

    try {
      final vigencia = await _repository.cambiarVigencia(
        configuracionCobroId: configuracionCobroId,
        datos: validacion.resultado!,
        etapas: validacionEtapas.resultado,
      );
      return CambiarVigenciaConfiguracionCobroExitoso(vigencia);
    } catch (e) {
      return CambiarVigenciaConfiguracionCobroErrorInesperado(e.toString());
    }
  }
}
