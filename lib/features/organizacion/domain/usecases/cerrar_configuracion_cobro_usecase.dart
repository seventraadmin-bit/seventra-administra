import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/utils/clock.dart';

import '../repositories/configuracion_cobro_repository.dart';
import 'configuracion_cobro_con_vigencia.dart';

sealed class CerrarConfiguracionCobroResultado {}

class CerrarConfiguracionCobroExitoso extends CerrarConfiguracionCobroResultado {
  CerrarConfiguracionCobroExitoso(this.vigencia);
  final ConfiguracionCobroVigenciaData vigencia;
}

/// No hay ninguna vigencia vigente hoy que cerrar.
class CerrarConfiguracionCobroSinCondicionVigente extends CerrarConfiguracionCobroResultado {}

/// Ya existe una vigencia programada — debe cancelarse primero.
class CerrarConfiguracionCobroTieneVigenciaProgramada extends CerrarConfiguracionCobroResultado {}

class CerrarConfiguracionCobroFechaAnteriorInicio extends CerrarConfiguracionCobroResultado {}

class CerrarConfiguracionCobroNoExiste extends CerrarConfiguracionCobroResultado {}

class CerrarConfiguracionCobroErrorInesperado extends CerrarConfiguracionCobroResultado {
  CerrarConfiguracionCobroErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cierra sin reemplazo la vigencia vigente actual de una Configuración
/// de cobro — acción administrativa explícita, deliberadamente NO
/// bloqueada por `Servicio.estatus == terminado` (mismo criterio que
/// `CerrarLineaComercialUseCase`, Etapa 4G.2).
class CerrarConfiguracionCobroUseCase {
  CerrarConfiguracionCobroUseCase(this._repository, this._clock);

  final ConfiguracionCobroRepository _repository;
  final Clock _clock;

  Future<CerrarConfiguracionCobroResultado> ejecutar({
    required String configuracionCobroId,
    required DateTime fechaEfectiva,
  }) async {
    final configuracion = await _repository.obtenerConfiguracionPorId(configuracionCobroId);
    if (configuracion == null) {
      return CerrarConfiguracionCobroNoExiste();
    }

    final historial = await _repository.listarHistorial(configuracionCobroId);
    final activas = historial.where((v) => v.cicloVidaRegistro == CicloVidaRegistro.activo.name).toList();
    final (:vigente, :programadas) = clasificarVigenciasCobro(activas, _clock.now());

    if (vigente == null) {
      return CerrarConfiguracionCobroSinCondicionVigente();
    }
    if (programadas.isNotEmpty) {
      return CerrarConfiguracionCobroTieneVigenciaProgramada();
    }
    if (soloFechaCobro(fechaEfectiva).isBefore(soloFechaCobro(vigente.fechaInicioVigencia))) {
      return CerrarConfiguracionCobroFechaAnteriorInicio();
    }

    try {
      final vigencia = await _repository.cerrarVigencia(vigenciaId: vigente.id, fechaEfectiva: fechaEfectiva);
      return CerrarConfiguracionCobroExitoso(vigencia);
    } catch (e) {
      return CerrarConfiguracionCobroErrorInesperado(e.toString());
    }
  }
}
