import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/utils/clock.dart';

import '../repositories/configuracion_cobro_repository.dart';
import 'configuracion_cobro_con_vigencia.dart';

sealed class ActualizarObservacionesConfiguracionCobroVigenciaResultado {}

class ActualizarObservacionesConfiguracionCobroVigenciaExitoso
    extends ActualizarObservacionesConfiguracionCobroVigenciaResultado {
  ActualizarObservacionesConfiguracionCobroVigenciaExitoso(this.vigencia);
  final ConfiguracionCobroVigenciaData vigencia;
}

/// No se editan observaciones de una vigencia histórica o cancelada —
/// son datos cerrados (mismo criterio que
/// `ActualizarAnotacionesVigenciaUseCase`, Etapa 4G.2).
class ActualizarObservacionesConfiguracionCobroVigenciaNoEditable
    extends ActualizarObservacionesConfiguracionCobroVigenciaResultado {}

class ActualizarObservacionesConfiguracionCobroVigenciaNoExiste
    extends ActualizarObservacionesConfiguracionCobroVigenciaResultado {}

class ActualizarObservacionesConfiguracionCobroVigenciaErrorInesperado
    extends ActualizarObservacionesConfiguracionCobroVigenciaResultado {
  ActualizarObservacionesConfiguracionCobroVigenciaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Edita únicamente `observaciones` sobre la misma vigencia — nunca
/// abre una nueva (Resolución A de la Etapa 4H.2, mismo criterio que
/// `ActualizarAnotacionesVigenciaUseCase`). Permitido sobre la vigente
/// actual o una programada; rechazado sobre histórica o cancelada.
class ActualizarObservacionesConfiguracionCobroVigenciaUseCase {
  ActualizarObservacionesConfiguracionCobroVigenciaUseCase(this._repository, this._clock);

  final ConfiguracionCobroRepository _repository;
  final Clock _clock;

  Future<ActualizarObservacionesConfiguracionCobroVigenciaResultado> ejecutar({
    required String vigenciaId,
    String? observaciones,
  }) async {
    final vigencia = await _repository.obtenerVigencia(vigenciaId);
    if (vigencia == null) {
      return ActualizarObservacionesConfiguracionCobroVigenciaNoExiste();
    }

    final estado = clasificarParaHistorialCobro(vigencia, _clock.now());
    if (estado == EstadoVigenciaCobro.historica || estado == EstadoVigenciaCobro.cancelada) {
      return ActualizarObservacionesConfiguracionCobroVigenciaNoEditable();
    }

    String? vacioANull(String? valor) {
      final recortado = valor?.trim();
      return (recortado == null || recortado.isEmpty) ? null : recortado;
    }

    try {
      final actualizada = await _repository.actualizarObservaciones(
        vigenciaId: vigenciaId,
        observaciones: vacioANull(observaciones),
      );
      return ActualizarObservacionesConfiguracionCobroVigenciaExitoso(actualizada);
    } catch (e) {
      return ActualizarObservacionesConfiguracionCobroVigenciaErrorInesperado(e.toString());
    }
  }
}
