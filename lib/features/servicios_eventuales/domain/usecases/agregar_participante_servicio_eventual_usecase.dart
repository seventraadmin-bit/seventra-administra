import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';

import '../../data/tables/servicio_eventual_table.dart';
import '../repositories/servicio_eventual_repository.dart';

sealed class AgregarParticipanteServicioEventualResultado {}

class AgregarParticipanteServicioEventualExitoso extends AgregarParticipanteServicioEventualResultado {
  AgregarParticipanteServicioEventualExitoso(this.participante);
  final ServicioEventualParticipanteData participante;
}

class AgregarParticipanteServicioEventualNoExiste extends AgregarParticipanteServicioEventualResultado {}

class AgregarParticipanteServicioEventualCancelado extends AgregarParticipanteServicioEventualResultado {}

/// O un empleado de la plantilla, o una persona externa con nombre.
/// Nunca los dos, nunca ninguno — misma regla que el `CHECK` del
/// esquema.
class AgregarParticipanteServicioEventualIdentidadInvalida
    extends AgregarParticipanteServicioEventualResultado {}

class AgregarParticipanteServicioEventualEmpleadoNoExiste
    extends AgregarParticipanteServicioEventualResultado {}

class AgregarParticipanteServicioEventualDuplicado extends AgregarParticipanteServicioEventualResultado {}

class AgregarParticipanteServicioEventualErrorInesperado
    extends AgregarParticipanteServicioEventualResultado {
  AgregarParticipanteServicioEventualErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Suma una persona al evento.
///
/// Un participante **no es una asignación a Servicio**: no toca
/// `AsignacionServicio`, no mueve la plantilla operativa ni la nómina.
/// Un eventual es trabajo puntual pagado por fuera de la quincena, y
/// por eso su costo vive en `ServicioEventualCobertura`.
class AgregarParticipanteServicioEventualUseCase {
  AgregarParticipanteServicioEventualUseCase(this._repository, this._empleadoRepository);

  final ServicioEventualRepository _repository;
  final EmpleadoRepository _empleadoRepository;

  Future<AgregarParticipanteServicioEventualResultado> ejecutar({
    required String servicioEventualId,
    String? empleadoId,
    String? nombreExterno,
    String? telefonoExterno,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    final eventual = await _repository.obtenerPorId(servicioEventualId);
    if (eventual == null) return AgregarParticipanteServicioEventualNoExiste();
    if (eventual.estatus == EstatusServicioEventual.cancelado.name) {
      return AgregarParticipanteServicioEventualCancelado();
    }

    final idEmpleado = (empleadoId ?? '').trim();
    final nombre = (nombreExterno ?? '').trim();
    if (idEmpleado.isEmpty == nombre.isEmpty) {
      return AgregarParticipanteServicioEventualIdentidadInvalida();
    }

    if (idEmpleado.isNotEmpty) {
      if (await _empleadoRepository.obtenerPorId(idEmpleado) == null) {
        return AgregarParticipanteServicioEventualEmpleadoNoExiste();
      }
      // El mismo empleado dos veces en el mismo evento sería contarle
      // dos veces sus coberturas. Un externo homónimo sí puede
      // repetirse: son dos personas distintas.
      final existentes = await _repository.listarParticipantes(servicioEventualId);
      if (existentes.any((p) => p.empleadoId == idEmpleado)) {
        return AgregarParticipanteServicioEventualDuplicado();
      }
    }

    try {
      final participante = await _repository.agregarParticipante(
        servicioEventualId: servicioEventualId,
        empleadoId: idEmpleado.isEmpty ? null : idEmpleado,
        nombreExterno: nombre.isEmpty ? null : nombre,
        telefonoExterno: idEmpleado.isEmpty ? _opcional(telefonoExterno) : null,
        observaciones: _opcional(observaciones),
        actorUsuarioId: actorUsuarioId,
      );
      return AgregarParticipanteServicioEventualExitoso(participante);
    } catch (e) {
      return AgregarParticipanteServicioEventualErrorInesperado(e.toString());
    }
  }
}

String? _opcional(String? valor) {
  final limpio = valor?.trim() ?? '';
  return limpio.isEmpty ? null : limpio;
}
