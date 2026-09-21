import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_table.dart';

import '../repositories/cliente_repository.dart';

/// Resultado de [CambiarEstatusClienteUseCase] — su propio tipo sellado,
/// mismo patrón que `CambiarCicloVidaPuestoResultado`.
sealed class CambiarEstatusClienteResultado {}

class CambiarEstatusClienteExitoso extends CambiarEstatusClienteResultado {
  CambiarEstatusClienteExitoso(this.cliente);
  final ClienteData cliente;
}

/// El motivo es obligatorio: un Cliente suspendido o terminado sin
/// explicación deja una decisión comercial sin dueño.
class CambiarEstatusClienteMotivoRequerido extends CambiarEstatusClienteResultado {}

class CambiarEstatusClienteErrorInesperado extends CambiarEstatusClienteResultado {
  CambiarEstatusClienteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cambia el estatus comercial de un Cliente (prospecto/activo/
/// suspendido/terminado/descartado) — cualquier transición entre estos
/// 5 valores está permitida en esta etapa; todavía no existe ninguna
/// entidad (Entidad fiscal, Servicio) que deba bloquearla.
class CambiarEstatusClienteUseCase {
  CambiarEstatusClienteUseCase(this._repository);

  final ClienteRepository _repository;

  Future<CambiarEstatusClienteResultado> ejecutar({
    required String clienteId,
    required EstatusCliente nuevo,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) return CambiarEstatusClienteMotivoRequerido();
    try {
      final actualizado = await _repository.cambiarEstatus(
        id: clienteId,
        nuevo: nuevo,
        motivo: motivo.trim(),
        actorUsuarioId: actorUsuarioId,
      );
      return CambiarEstatusClienteExitoso(actualizado);
    } catch (e) {
      return CambiarEstatusClienteErrorInesperado(e.toString());
    }
  }
}
