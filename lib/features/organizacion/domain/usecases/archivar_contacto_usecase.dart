import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/cliente_repository.dart';

/// Resultado de [ArchivarContactoUseCase] — su propio tipo sellado,
/// mismo patrón que `CambiarCicloVidaEntidadFiscalResultado`.
sealed class ArchivarContactoResultado {}

class ArchivarContactoExitoso extends ArchivarContactoResultado {
  ArchivarContactoExitoso(this.contacto);
  final ContactoData contacto;
}

/// Archivar un Contacto es una baja documental: retira de la vista a la
/// persona con la que se trata el Servicio. Exige explicar por qué.
class ArchivarContactoMotivoRequerido extends ArchivarContactoResultado {}

class ArchivarContactoErrorInesperado extends ArchivarContactoResultado {
  ArchivarContactoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Archivar un Contacto siempre está permitido — no hay ninguna entidad
/// que dependa de un Contacto específico en esta etapa (a diferencia de
/// Puesto↔Área). Nunca es un `hard delete`.
class ArchivarContactoUseCase {
  ArchivarContactoUseCase(this._repository);

  final ClienteRepository _repository;

  Future<ArchivarContactoResultado> ejecutar(
    String contactoId, {
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) return ArchivarContactoMotivoRequerido();
    try {
      final archivado = await _repository.archivarContacto(
        contactoId,
        motivo: motivo.trim(),
        actorUsuarioId: actorUsuarioId,
      );
      return ArchivarContactoExitoso(archivado);
    } catch (e) {
      return ArchivarContactoErrorInesperado(e.toString());
    }
  }
}
