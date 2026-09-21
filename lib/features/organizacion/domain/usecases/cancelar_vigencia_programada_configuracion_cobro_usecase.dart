import 'package:riseg_one/core/utils/clock.dart';

import 'package:riseg_one/core/auditoria/diff_evento.dart';
import '../repositories/configuracion_cobro_repository.dart';
import 'configuracion_cobro_con_vigencia.dart';

sealed class CancelarVigenciaProgramadaConfiguracionCobroResultado {}

class CancelarVigenciaProgramadaConfiguracionCobroExitoso extends CancelarVigenciaProgramadaConfiguracionCobroResultado {}

/// La vigencia ya no está programada — o su fecha ya llegó, o ya estaba
/// cancelada.
class CancelarVigenciaProgramadaConfiguracionCobroNoEsProgramada
    extends CancelarVigenciaProgramadaConfiguracionCobroResultado {}

class CancelarVigenciaProgramadaConfiguracionCobroNoExiste extends CancelarVigenciaProgramadaConfiguracionCobroResultado {}

/// Cancelar una vigencia de cobro programada exige explicar por qué.
class CancelarVigenciaProgramadaConfiguracionCobroMotivoRequerido
    extends CancelarVigenciaProgramadaConfiguracionCobroResultado {}

class CancelarVigenciaProgramadaConfiguracionCobroErrorInesperado
    extends CancelarVigenciaProgramadaConfiguracionCobroResultado {
  CancelarVigenciaProgramadaConfiguracionCobroErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cancela una vigencia programada antes de que entre en vigor — mismo
/// criterio que `CancelarVigenciaProgramadaUseCase` (Etapa 4G.2,
/// Resolución F): trazabilidad completa, la vigencia cancelada nunca se
/// borra ni se oculta del historial.
class CancelarVigenciaProgramadaConfiguracionCobroUseCase {
  CancelarVigenciaProgramadaConfiguracionCobroUseCase(this._repository, this._clock);

  final ConfiguracionCobroRepository _repository;
  final Clock _clock;

  Future<CancelarVigenciaProgramadaConfiguracionCobroResultado> ejecutar({
    required String vigenciaId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) return CancelarVigenciaProgramadaConfiguracionCobroMotivoRequerido();
    final vigencia = await _repository.obtenerVigencia(vigenciaId);
    if (vigencia == null) {
      return CancelarVigenciaProgramadaConfiguracionCobroNoExiste();
    }

    final estado = clasificarParaHistorialCobro(vigencia, _clock.now());
    if (estado != EstadoVigenciaCobro.programada) {
      return CancelarVigenciaProgramadaConfiguracionCobroNoEsProgramada();
    }

    try {
      await _repository.cancelarVigenciaProgramada(
        vigenciaId,
        motivo: motivo.trim(),
        actorUsuarioId: actorUsuarioId,
      );
      return CancelarVigenciaProgramadaConfiguracionCobroExitoso();
    } catch (e) {
      return CancelarVigenciaProgramadaConfiguracionCobroErrorInesperado(e.toString());
    }
  }
}
