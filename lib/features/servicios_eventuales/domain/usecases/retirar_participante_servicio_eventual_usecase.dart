import '../repositories/servicio_eventual_repository.dart';

sealed class RetirarParticipanteServicioEventualResultado {}

class RetirarParticipanteServicioEventualExitoso extends RetirarParticipanteServicioEventualResultado {}

class RetirarParticipanteServicioEventualNoExiste extends RetirarParticipanteServicioEventualResultado {}

/// El participante ya tiene coberturas registradas — retirarlo
/// borraría trabajo comprometido (y, si alguna está pagada, dinero ya
/// movido). Se cancelan primero sus coberturas, una por una y con
/// motivo.
class RetirarParticipanteServicioEventualTieneCoberturas
    extends RetirarParticipanteServicioEventualResultado {
  RetirarParticipanteServicioEventualTieneCoberturas(this.cantidad);
  final int cantidad;
}

class RetirarParticipanteServicioEventualErrorInesperado
    extends RetirarParticipanteServicioEventualResultado {
  RetirarParticipanteServicioEventualErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Quita del evento a alguien que nunca llegó a tener coberturas —un
/// error de captura, típicamente—. No es una "baja": un participante
/// que sí trabajó se conserva siempre, con sus coberturas canceladas o
/// pagadas según lo que haya ocurrido.
class RetirarParticipanteServicioEventualUseCase {
  RetirarParticipanteServicioEventualUseCase(this._repository);

  final ServicioEventualRepository _repository;

  Future<RetirarParticipanteServicioEventualResultado> ejecutar({
    required String participanteId,
    String? actorUsuarioId,
  }) async {
    // Se cuentan TODAS las coberturas, incluidas las canceladas: la
    // historia del participante ya existe y borrarla dejaría eventos
    // apuntando a una fila inexistente.
    final coberturas = await _repository.listarCoberturasPorParticipante(participanteId);
    if (coberturas.isNotEmpty) {
      return RetirarParticipanteServicioEventualTieneCoberturas(coberturas.length);
    }

    try {
      await _repository.retirarParticipante(
        participanteId: participanteId,
        actorUsuarioId: actorUsuarioId,
      );
      return RetirarParticipanteServicioEventualExitoso();
    } on StateError {
      return RetirarParticipanteServicioEventualNoExiste();
    } catch (e) {
      return RetirarParticipanteServicioEventualErrorInesperado(e.toString());
    }
  }
}
