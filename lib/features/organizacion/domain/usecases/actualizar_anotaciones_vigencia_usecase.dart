import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/utils/clock.dart';

import '../repositories/servicio_comercial_repository.dart';
import 'linea_comercial_con_vigencia.dart';

sealed class ActualizarAnotacionesVigenciaResultado {}

class ActualizarAnotacionesVigenciaExitoso extends ActualizarAnotacionesVigenciaResultado {
  ActualizarAnotacionesVigenciaExitoso(this.vigencia);
  final ServicioLineaComercialVigenciaData vigencia;
}

/// No se edita descripción/observaciones de una vigencia histórica o
/// cancelada — son datos cerrados (Etapa 4G.2: "no modificar documentos
/// históricos ni condiciones cerradas").
class ActualizarAnotacionesVigenciaNoEditable extends ActualizarAnotacionesVigenciaResultado {}

class ActualizarAnotacionesVigenciaNoExiste extends ActualizarAnotacionesVigenciaResultado {}

class ActualizarAnotacionesVigenciaErrorInesperado extends ActualizarAnotacionesVigenciaResultado {
  ActualizarAnotacionesVigenciaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Edita únicamente descripción/observaciones sobre la misma vigencia —
/// nunca abre una nueva (Etapa 4G.2, Resolución A). Permitido sobre la
/// vigente actual o una programada; rechazado sobre histórica o
/// cancelada.
class ActualizarAnotacionesVigenciaUseCase {
  ActualizarAnotacionesVigenciaUseCase(this._repository, this._clock);

  final ServicioComercialRepository _repository;
  final Clock _clock;

  Future<ActualizarAnotacionesVigenciaResultado> ejecutar({
    required String vigenciaId,
    String? descripcion,
    String? observaciones,
  }) async {
    final vigencia = await _repository.obtenerVigencia(vigenciaId);
    if (vigencia == null) {
      return ActualizarAnotacionesVigenciaNoExiste();
    }

    final estado = clasificarParaHistorial(vigencia, _clock.now());
    if (estado == EstadoVigencia.historica || estado == EstadoVigencia.cancelada) {
      return ActualizarAnotacionesVigenciaNoEditable();
    }

    String? vacioANull(String? valor) {
      final recortado = valor?.trim();
      return (recortado == null || recortado.isEmpty) ? null : recortado;
    }

    try {
      final actualizada = await _repository.actualizarAnotaciones(
        vigenciaId: vigenciaId,
        descripcion: vacioANull(descripcion),
        observaciones: vacioANull(observaciones),
      );
      return ActualizarAnotacionesVigenciaExitoso(actualizada);
    } catch (e) {
      return ActualizarAnotacionesVigenciaErrorInesperado(e.toString());
    }
  }
}
