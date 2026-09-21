import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';

import '../repositories/servicio_comercial_repository.dart';
import '../repositories/servicio_repository.dart';
import 'linea_comercial_errors.dart';
import 'linea_comercial_validator.dart';

sealed class CambiarVigenciaLineaComercialResultado {}

class CambiarVigenciaLineaComercialExitoso extends CambiarVigenciaLineaComercialResultado {
  CambiarVigenciaLineaComercialExitoso(this.vigencia);
  final ServicioLineaComercialVigenciaData vigencia;
}

class CambiarVigenciaLineaComercialErroresValidacion extends CambiarVigenciaLineaComercialResultado {
  CambiarVigenciaLineaComercialErroresValidacion(this.errores);
  final List<ErrorLineaComercial> errores;
}

class CambiarVigenciaLineaComercialLineaNoExiste extends CambiarVigenciaLineaComercialResultado {}

/// Mismo criterio que `CrearLineaComercialUseCase`: un Servicio
/// `terminado` no admite nuevas condiciones comerciales. Cerrar una
/// línea o cancelar una programada NO pasan por este bloqueo — solo
/// registrar una condición nueva.
class CambiarVigenciaLineaComercialServicioNoDisponible extends CambiarVigenciaLineaComercialResultado {}

class CambiarVigenciaLineaComercialErrorInesperado extends CambiarVigenciaLineaComercialResultado {
  CambiarVigenciaLineaComercialErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra una nueva vigencia sobre una línea ya existente — reemplaza
/// la vigente actual (si la fecha efectiva es hoy) o queda programada
/// (si es futura); nunca actualiza in place puesto/cantidad/turno/
/// precio/IVA/fecha (Etapa 4G.2). Retroactivo (fecha en el pasado) está
/// permitido — la UI exige una confirmación explícita antes de llamar
/// aquí (Resolución H); esta regla se endurecerá para rechazarlo cuando
/// exista Configuración de cobro/Facturación.
class CambiarVigenciaLineaComercialUseCase {
  CambiarVigenciaLineaComercialUseCase(this._repository, this._servicioRepository, this._validator);

  final ServicioComercialRepository _repository;
  final ServicioRepository _servicioRepository;
  final LineaComercialValidator _validator;

  /// [observacion] es opcional: abrir una vigencia nueva NO es corregir
  /// nada. La anterior queda intacta, cerrada en su fecha.
  Future<CambiarVigenciaLineaComercialResultado> ejecutar({
    required String lineaComercialId,
    required LineaComercialBorrador borrador,
    String? observacion,
    String? actorUsuarioId,
  }) async {
    final linea = await _repository.obtenerLinea(lineaComercialId);
    if (linea == null) {
      return CambiarVigenciaLineaComercialLineaNoExiste();
    }

    final servicio = await _servicioRepository.obtenerPorId(linea.servicioId);
    if (servicio != null && EstatusServicio.values.byName(servicio.estatus) == EstatusServicio.terminado) {
      return CambiarVigenciaLineaComercialServicioNoDisponible();
    }

    final historial = await _repository.listarHistorial(lineaComercialId);
    final vigenciasActivas = historial.where((v) => v.cicloVidaRegistro == CicloVidaRegistro.activo.name).toList();

    final validacion = await _validator.validarNuevaVigencia(
      servicioId: linea.servicioId,
      borrador: borrador,
      vigenciasExistentes: vigenciasActivas,
    );
    if (validacion.errores.isNotEmpty) {
      return CambiarVigenciaLineaComercialErroresValidacion(validacion.errores);
    }

    try {
      final vigencia = await _repository.cambiarVigencia(
        lineaComercialId: lineaComercialId,
        datos: validacion.resultado!,
        observacion: observacion,
        actorUsuarioId: actorUsuarioId,
      );
      return CambiarVigenciaLineaComercialExitoso(vigencia);
    } catch (e) {
      return CambiarVigenciaLineaComercialErrorInesperado(e.toString());
    }
  }
}
