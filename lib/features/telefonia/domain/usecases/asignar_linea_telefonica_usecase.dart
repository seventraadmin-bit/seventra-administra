import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/asignacion_linea_telefonica_repository.dart';
import '../repositories/linea_telefonica_equipo_repository.dart';
import '../repositories/linea_telefonica_repository.dart';

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

class AsignarLineaTelefonicaErrorInesperado extends AsignarLineaTelefonicaResultado {
  AsignarLineaTelefonicaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Asigna una línea sin destino a un Empleado o a un Servicio (Etapa
/// 9B). Si [moverEquipoAsociado] (default `true`) y la línea ya tiene
/// un equipo asociado, sincroniza la custodia real en Inventario con el
/// nuevo destino — nunca automático y silencioso: la UI siempre expone
/// esta opción de forma explícita (punto 7 de Marlon: "no quiero
/// automatismos sorprendentes").
class AsignarLineaTelefonicaUseCase {
  AsignarLineaTelefonicaUseCase(this._lineaRepository, this._asignacionRepository, this._equipoRepository);

  final LineaTelefonicaRepository _lineaRepository;
  final AsignacionLineaTelefonicaRepository _asignacionRepository;
  final LineaTelefonicaEquipoRepository _equipoRepository;

  Future<AsignarLineaTelefonicaResultado> ejecutar({
    required String lineaTelefonicaId,
    String? empleadoId,
    String? servicioId,
    required DateTime fechaInicio,
    String? observaciones,
    bool moverEquipoAsociado = true,
    String? actor,
  }) async {
    if ((empleadoId == null) == (servicioId == null)) return AsignarLineaTelefonicaDestinoInvalido();

    final linea = await _lineaRepository.obtenerPorId(lineaTelefonicaId);
    if (linea == null) return AsignarLineaTelefonicaNoExiste();
    if (linea.estatus == 'baja') return AsignarLineaTelefonicaLineaDeBaja();

    final vigente = await _asignacionRepository.obtenerActivaPorLinea(lineaTelefonicaId);
    if (vigente != null) return AsignarLineaTelefonicaYaAsignada();

    try {
      final asignacion = await _asignacionRepository.crear(
        lineaTelefonicaId: lineaTelefonicaId,
        empleadoId: empleadoId,
        servicioId: servicioId,
        fechaInicio: fechaInicio,
        observaciones: observaciones,
        actor: actor,
      );

      if (moverEquipoAsociado) {
        await _equipoRepository.sincronizarConAsignacionVigente(
          lineaTelefonicaId: lineaTelefonicaId,
          fecha: fechaInicio,
        );
      }

      return AsignarLineaTelefonicaExitoso(asignacion);
    } catch (e) {
      return AsignarLineaTelefonicaErrorInesperado(e.toString());
    }
  }
}
