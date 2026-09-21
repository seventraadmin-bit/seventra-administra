import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/servicio_eventual_table.dart';
import '../repositories/servicio_eventual_repository.dart';

sealed class AgregarCoberturaServicioEventualResultado {}

class AgregarCoberturaServicioEventualExitoso extends AgregarCoberturaServicioEventualResultado {
  AgregarCoberturaServicioEventualExitoso(this.cobertura);
  final ServicioEventualCoberturaData cobertura;
}

class AgregarCoberturaServicioEventualNoExiste extends AgregarCoberturaServicioEventualResultado {}

class AgregarCoberturaServicioEventualCancelado extends AgregarCoberturaServicioEventualResultado {}

/// El participante no existe o pertenece a OTRO eventual — una
/// cobertura jamás cruza de evento.
class AgregarCoberturaServicioEventualParticipanteInvalido
    extends AgregarCoberturaServicioEventualResultado {}

/// Hora fuera de `0..1439`, o inicio igual a fin (una cobertura de
/// cero minutos no es una cobertura).
class AgregarCoberturaServicioEventualHorarioInvalido extends AgregarCoberturaServicioEventualResultado {}

class AgregarCoberturaServicioEventualImporteInvalido extends AgregarCoberturaServicioEventualResultado {}

class AgregarCoberturaServicioEventualErrorInesperado extends AgregarCoberturaServicioEventualResultado {
  AgregarCoberturaServicioEventualErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra lo que una persona va a cubrir y cuánto se le pagará por
/// ello.
///
/// **Programar no mueve dinero.** La cobertura nace `programada` y sin
/// origen financiero; el Egreso —o el cargo a la tarjeta— aparece
/// únicamente al pagarla (`PagarCoberturaServicioEventualUseCase`).
/// Un turno que cruza la medianoche es normal en seguridad y se
/// representa con `horaFin < horaInicio`; la duración la resuelve
/// `duracionCoberturaMinutos`, nunca una resta directa.
class AgregarCoberturaServicioEventualUseCase {
  AgregarCoberturaServicioEventualUseCase(this._repository);

  final ServicioEventualRepository _repository;

  Future<AgregarCoberturaServicioEventualResultado> ejecutar({
    required String servicioEventualId,
    required String participanteId,
    required DateTime fecha,
    required int horaInicioMinutos,
    required int horaFinMinutos,
    String? descripcionHorario,
    required int importeAcordado,
    String? actorUsuarioId,
  }) async {
    final eventual = await _repository.obtenerPorId(servicioEventualId);
    if (eventual == null) return AgregarCoberturaServicioEventualNoExiste();
    if (eventual.estatus == EstatusServicioEventual.cancelado.name) {
      return AgregarCoberturaServicioEventualCancelado();
    }

    final participantes = await _repository.listarParticipantes(servicioEventualId);
    if (!participantes.any((p) => p.id == participanteId)) {
      return AgregarCoberturaServicioEventualParticipanteInvalido();
    }

    if (!_horaValida(horaInicioMinutos) ||
        !_horaValida(horaFinMinutos) ||
        horaInicioMinutos == horaFinMinutos) {
      return AgregarCoberturaServicioEventualHorarioInvalido();
    }
    if (importeAcordado <= 0) return AgregarCoberturaServicioEventualImporteInvalido();

    try {
      final cobertura = await _repository.agregarCobertura(
        servicioEventualId: servicioEventualId,
        participanteId: participanteId,
        fecha: fecha,
        horaInicioMinutos: horaInicioMinutos,
        horaFinMinutos: horaFinMinutos,
        descripcionHorario: descripcionHorario?.trim().isEmpty ?? true ? null : descripcionHorario!.trim(),
        importeAcordado: importeAcordado,
        actorUsuarioId: actorUsuarioId,
      );
      return AgregarCoberturaServicioEventualExitoso(cobertura);
    } catch (e) {
      return AgregarCoberturaServicioEventualErrorInesperado(e.toString());
    }
  }
}

bool _horaValida(int minutos) => minutos >= 0 && minutos <= 1439;
