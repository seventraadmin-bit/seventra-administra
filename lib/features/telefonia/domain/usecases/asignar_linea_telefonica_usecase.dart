import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/linea_telefonica_table.dart' show TipoEventoLineaTelefonica;
import '../coherencia_linea_equipo.dart';
import '../repositories/asignacion_linea_telefonica_repository.dart';
import '../repositories/linea_telefonica_equipo_repository.dart';
import '../repositories/linea_telefonica_repository.dart';
import 'obtener_coherencia_linea_equipo_usecase.dart';

sealed class AsignarLineaTelefonicaResultado {}

class AsignarLineaTelefonicaExitoso extends AsignarLineaTelefonicaResultado {
  AsignarLineaTelefonicaExitoso(this.asignacion);
  final AsignacionLineaTelefonicaData asignacion;
}

class AsignarLineaTelefonicaNoExiste extends AsignarLineaTelefonicaResultado {}

/// Exactamente uno de empleado/servicio debe venir poblado.
class AsignarLineaTelefonicaDestinoInvalido extends AsignarLineaTelefonicaResultado {}

/// La línea ya tiene una asignación vigente — usa
/// `CambiarAsignacionLineaTelefonicaUseCase`.
class AsignarLineaTelefonicaYaAsignada extends AsignarLineaTelefonicaResultado {}

class AsignarLineaTelefonicaLineaDeBaja extends AsignarLineaTelefonicaResultado {}

/// El destino pedido dejaría la línea en contradicción con la custodia
/// del equipo que la trae. [coherencia] dice exactamente cuál de las
/// dos contradicciones sería, con los destinos reales.
class AsignarLineaTelefonicaIncoherenteConEquipo extends AsignarLineaTelefonicaResultado {
  AsignarLineaTelefonicaIncoherenteConEquipo(this.coherencia);
  final CoherenciaLineaEquipo coherencia;
}

/// La operación corrige una incoherencia histórica: eso exige motivo.
class AsignarLineaTelefonicaMotivoRequerido extends AsignarLineaTelefonicaResultado {}

class AsignarLineaTelefonicaErrorInesperado extends AsignarLineaTelefonicaResultado {
  AsignarLineaTelefonicaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Asigna una línea sin destino a un Empleado o a un Servicio (Etapa
/// 9B).
///
/// **Nunca mueve la custodia del equipo** (Rebanada 2). Antes lo hacía
/// —`moverEquipoAsociado` empujaba la `Asignacion` de Inventario al
/// destino de la línea—; hoy Inventario es el dueño de la custodia y la
/// línea se limita a no contradecirla: si el equipo asociado está bajo
/// custodia de alguien, la línea sólo puede asignarse a ESE destino.
///
/// El camino natural para el caso contrario es el inverso: se asigna el
/// teléfono en Inventario y la asignación de la línea lo sigue sola.
class AsignarLineaTelefonicaUseCase {
  AsignarLineaTelefonicaUseCase(
    this._lineaRepository,
    AsignacionLineaTelefonicaRepository asignacionRepository,
    LineaTelefonicaEquipoRepository equipoRepository,
  )   : _asignacionRepository = asignacionRepository,
        _coherencia = ObtenerCoherenciaLineaEquipoUseCase(equipoRepository, asignacionRepository);

  final LineaTelefonicaRepository _lineaRepository;
  final AsignacionLineaTelefonicaRepository _asignacionRepository;
  final ObtenerCoherenciaLineaEquipoUseCase _coherencia;

  Future<AsignarLineaTelefonicaResultado> ejecutar({
    required String lineaTelefonicaId,
    String? empleadoId,
    String? servicioId,
    required DateTime fechaInicio,
    String? observaciones,
    String? motivo,
    String? actorUsuarioId,
  }) async {
    if ((empleadoId == null) == (servicioId == null)) return AsignarLineaTelefonicaDestinoInvalido();

    final linea = await _lineaRepository.obtenerPorId(lineaTelefonicaId);
    if (linea == null) return AsignarLineaTelefonicaNoExiste();
    if (linea.estatus == 'baja') return AsignarLineaTelefonicaLineaDeBaja();

    final vigente = await _asignacionRepository.obtenerActivaPorLinea(lineaTelefonicaId);
    if (vigente != null) return AsignarLineaTelefonicaYaAsignada();

    final antes = await _coherencia.ejecutar(lineaTelefonicaId);
    final cambio = CambioAsignacionLinea(
      antes: antes,
      despues: evaluarCoherenciaLineaEquipo(
        unidadId: antes.unidadId,
        destinoLinea: destinoDe(empleadoId: empleadoId, servicioId: servicioId),
        destinoEquipo: antes.destinoEquipo,
        pendienteRecuperacionDesde: antes.pendienteRecuperacionDesde,
      ),
    );

    if (cambio.dejariaContradiccion) {
      return AsignarLineaTelefonicaIncoherenteConEquipo(cambio.despues);
    }
    final esResolucion = cambio.esResolucionDeInconsistencia;
    if (esResolucion && !motivoEsValido(motivo ?? '')) {
      return AsignarLineaTelefonicaMotivoRequerido();
    }

    try {
      final asignacion = await _asignacionRepository.crear(
        lineaTelefonicaId: lineaTelefonicaId,
        empleadoId: empleadoId,
        servicioId: servicioId,
        fechaInicio: fechaInicio,
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );

      if (esResolucion) {
        await _registrarResolucion(
          lineaTelefonicaId: lineaTelefonicaId,
          antes: cambio.antes,
          despues: cambio.despues,
          motivo: motivo!.trim(),
          actorUsuarioId: actorUsuarioId,
        );
      }

      return AsignarLineaTelefonicaExitoso(asignacion);
    } catch (e) {
      return AsignarLineaTelefonicaErrorInesperado(e.toString());
    }
  }

  Future<void> _registrarResolucion({
    required String lineaTelefonicaId,
    required CoherenciaLineaEquipo antes,
    required CoherenciaLineaEquipo despues,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return registrarResolucionDeIncoherencia(
      lineaRepository: _lineaRepository,
      lineaTelefonicaId: lineaTelefonicaId,
      antes: antes,
      despues: despues,
      motivo: motivo,
      actorUsuarioId: actorUsuarioId,
    );
  }
}

/// Deja constancia de la corrección administrativa: actor, fecha,
/// estado de coherencia anterior y nuevo, motivo, línea y equipo
/// involucrado (§22). Compartido por las tres operaciones de asignación
/// de línea para que el asiento sea idéntico venga de donde venga.
Future<void> registrarResolucionDeIncoherencia({
  required LineaTelefonicaRepository lineaRepository,
  required String lineaTelefonicaId,
  required CoherenciaLineaEquipo antes,
  required CoherenciaLineaEquipo despues,
  required String motivo,
  String? actorUsuarioId,
}) {
  final diff = DiffEvento()
    ..anotar('coherenciaLineaEquipo', antes.estado.name, despues.estado.name)
    ..anotar('destinoLinea', antes.destinoLinea?.toString(), despues.destinoLinea?.toString())
    ..anotar('equipo', antes.unidadId, despues.unidadId);

  return lineaRepository.registrarEvento(
    lineaTelefonicaId: lineaTelefonicaId,
    tipoEvento: TipoEventoLineaTelefonica.incoherenciaResuelta,
    observacion: motivo,
    estadoAnterior: diff.estadoAnteriorJson,
    estadoNuevo: diff.estadoNuevoJson,
    actorUsuarioId: actorUsuarioId,
  );
}
