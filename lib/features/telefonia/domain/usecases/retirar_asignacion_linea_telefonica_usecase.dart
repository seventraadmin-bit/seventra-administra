import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/asignacion_linea_telefonica_table.dart' show MotivoTerminoAsignacionLineaTelefonica;
import '../coherencia_linea_equipo.dart';
import '../repositories/asignacion_linea_telefonica_repository.dart';
import '../repositories/linea_telefonica_equipo_repository.dart';
import '../repositories/linea_telefonica_repository.dart';
import 'asignar_linea_telefonica_usecase.dart' show registrarResolucionDeIncoherencia;
import 'obtener_coherencia_linea_equipo_usecase.dart';

sealed class RetirarAsignacionLineaTelefonicaResultado {}

class RetirarAsignacionLineaTelefonicaExitoso extends RetirarAsignacionLineaTelefonicaResultado {
  RetirarAsignacionLineaTelefonicaExitoso(this.asignacion);
  final AsignacionLineaTelefonicaData asignacion;
}

class RetirarAsignacionLineaTelefonicaNoExiste extends RetirarAsignacionLineaTelefonicaResultado {}

class RetirarAsignacionLineaTelefonicaYaCerrada extends RetirarAsignacionLineaTelefonicaResultado {}

/// §12 — el equipo asociado sigue en manos de alguien. Dejar la línea
/// sin asignación mientras su teléfono está custodiado reproduce
/// exactamente el caso real que originó esta rebanada.
class RetirarAsignacionLineaTelefonicaEquipoCustodiado extends RetirarAsignacionLineaTelefonicaResultado {
  RetirarAsignacionLineaTelefonicaEquipoCustodiado(this.coherencia);
  final CoherenciaLineaEquipo coherencia;
}

class RetirarAsignacionLineaTelefonicaMotivoRequerido extends RetirarAsignacionLineaTelefonicaResultado {}

class RetirarAsignacionLineaTelefonicaErrorInesperado extends RetirarAsignacionLineaTelefonicaResultado {
  RetirarAsignacionLineaTelefonicaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Libera una línea telefónica (Etapa 9B) — cierra la asignación
/// vigente con motivo `liberacion`.
///
/// **Nunca libera la custodia del equipo** (Rebanada 2). Y, al revés,
/// tampoco deja la línea huérfana mientras el aparato sigue custodiado:
/// para eso hay que retirar antes el equipo de la línea (operación
/// puramente telefónica, siempre permitida) o devolver el aparato en
/// Inventario, que cierra la asignación de la línea por sí solo.
class RetirarAsignacionLineaTelefonicaUseCase {
  RetirarAsignacionLineaTelefonicaUseCase(
    AsignacionLineaTelefonicaRepository asignacionRepository,
    LineaTelefonicaEquipoRepository equipoRepository,
    this._lineaRepository,
  )   : _asignacionRepository = asignacionRepository,
        _coherencia = ObtenerCoherenciaLineaEquipoUseCase(equipoRepository, asignacionRepository);

  final AsignacionLineaTelefonicaRepository _asignacionRepository;
  final LineaTelefonicaRepository _lineaRepository;
  final ObtenerCoherenciaLineaEquipoUseCase _coherencia;

  Future<RetirarAsignacionLineaTelefonicaResultado> ejecutar({
    required String asignacionLineaTelefonicaId,
    required DateTime fechaTermino,
    String? observacionesTermino,
    String? motivo,
    String? actorUsuarioId,
  }) async {
    final actual = await _asignacionRepository.obtenerPorId(asignacionLineaTelefonicaId);
    if (actual == null) return RetirarAsignacionLineaTelefonicaNoExiste();
    if (actual.fechaTermino != null) return RetirarAsignacionLineaTelefonicaYaCerrada();

    final antes = await _coherencia.ejecutar(actual.lineaTelefonicaId);
    final cambio = CambioAsignacionLinea(
      antes: antes,
      despues: evaluarCoherenciaLineaEquipo(
        unidadId: antes.unidadId,
        destinoLinea: null,
        destinoEquipo: antes.destinoEquipo,
        pendienteRecuperacionDesde: antes.pendienteRecuperacionDesde,
      ),
    );

    if (cambio.dejariaContradiccion) {
      return RetirarAsignacionLineaTelefonicaEquipoCustodiado(cambio.despues);
    }
    final esResolucion = cambio.esResolucionDeInconsistencia;
    if (esResolucion && !motivoEsValido(motivo ?? '')) {
      return RetirarAsignacionLineaTelefonicaMotivoRequerido();
    }

    try {
      final cerrada = await _asignacionRepository.cerrar(
        asignacionLineaTelefonicaId: asignacionLineaTelefonicaId,
        fechaTermino: fechaTermino,
        motivoTermino: MotivoTerminoAsignacionLineaTelefonica.liberacion.name,
        observacionesTermino: observacionesTermino,
        actorUsuarioId: actorUsuarioId,
      );

      if (esResolucion) {
        await registrarResolucionDeIncoherencia(
          lineaRepository: _lineaRepository,
          lineaTelefonicaId: actual.lineaTelefonicaId,
          antes: cambio.antes,
          despues: cambio.despues,
          motivo: motivo!.trim(),
          actorUsuarioId: actorUsuarioId,
        );
      }

      return RetirarAsignacionLineaTelefonicaExitoso(cerrada);
    } catch (e) {
      return RetirarAsignacionLineaTelefonicaErrorInesperado(e.toString());
    }
  }
}
