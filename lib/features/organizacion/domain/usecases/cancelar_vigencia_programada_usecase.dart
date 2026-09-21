import 'package:riseg_one/core/utils/clock.dart';

import 'package:riseg_one/core/auditoria/diff_evento.dart';
import '../repositories/servicio_comercial_repository.dart';
import 'linea_comercial_con_vigencia.dart';

sealed class CancelarVigenciaProgramadaResultado {}

class CancelarVigenciaProgramadaExitoso extends CancelarVigenciaProgramadaResultado {}

/// La vigencia ya no está programada — o porque su fecha ya llegó (es
/// la vigente actual o ya es histórica), o porque ya estaba cancelada.
/// Nunca se cancela nada más que una programada genuina.
class CancelarVigenciaProgramadaNoEsProgramada extends CancelarVigenciaProgramadaResultado {}

class CancelarVigenciaProgramadaNoExiste extends CancelarVigenciaProgramadaResultado {}

/// Cancelar una vigencia programada exige explicar por qué.
class CancelarVigenciaProgramadaMotivoRequerido extends CancelarVigenciaProgramadaResultado {}

class CancelarVigenciaProgramadaErrorInesperado extends CancelarVigenciaProgramadaResultado {
  CancelarVigenciaProgramadaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cancela una vigencia programada antes de que entre en vigor — la
/// forma de "corregir" una programada (Etapa 4G.2, Resolución F):
/// cancelar + registrar una nueva, nunca editarla in place. Preserva
/// trazabilidad completa: la vigencia cancelada nunca se borra ni se
/// oculta del historial, solo deja de poder participar en cálculos o
/// volver a activarse.
class CancelarVigenciaProgramadaUseCase {
  CancelarVigenciaProgramadaUseCase(this._repository, this._clock);

  final ServicioComercialRepository _repository;
  final Clock _clock;

  /// [motivo] obligatorio: cancelar una vigencia programada retira
  /// condiciones que ya estaban decididas. La vigencia NO se borra —
  /// queda archivada y visible en el historial.
  Future<CancelarVigenciaProgramadaResultado> ejecutar({
    required String vigenciaId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) return CancelarVigenciaProgramadaMotivoRequerido();
    final vigencia = await _repository.obtenerVigencia(vigenciaId);
    if (vigencia == null) {
      return CancelarVigenciaProgramadaNoExiste();
    }

    final estado = clasificarParaHistorial(vigencia, _clock.now());
    if (estado != EstadoVigencia.programada) {
      return CancelarVigenciaProgramadaNoEsProgramada();
    }

    try {
      await _repository.cancelarVigenciaProgramada(
        vigenciaId,
        motivo: motivo.trim(),
        actorUsuarioId: actorUsuarioId,
      );
      return CancelarVigenciaProgramadaExitoso();
    } catch (e) {
      return CancelarVigenciaProgramadaErrorInesperado(e.toString());
    }
  }
}
