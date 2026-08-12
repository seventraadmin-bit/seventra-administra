import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/boveda_credencial_repository.dart';

sealed class ReactivarCredencialBovedaResultado {}

class ReactivarCredencialBovedaExitoso extends ReactivarCredencialBovedaResultado {
  ReactivarCredencialBovedaExitoso(this.credencial);
  final BovedaCredencialData credencial;
}

class ReactivarCredencialBovedaErrorInesperado extends ReactivarCredencialBovedaResultado {
  ReactivarCredencialBovedaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Reactivar una credencial de la Bóveda nunca está bloqueado (Etapa
/// 14D) — mismo criterio que `ActivarAreaUseCase`.
class ReactivarCredencialBovedaUseCase {
  ReactivarCredencialBovedaUseCase(this._repository);

  final BovedaCredencialRepository _repository;

  Future<ReactivarCredencialBovedaResultado> ejecutar({required String id, String? actorUsuarioId}) async {
    try {
      final credencial = await _repository.reactivar(id);
      await _repository.registrarEvento(credencialId: id, tipoEvento: 'reactivada', actorUsuarioId: actorUsuarioId);
      return ReactivarCredencialBovedaExitoso(credencial);
    } catch (e) {
      return ReactivarCredencialBovedaErrorInesperado(e.toString());
    }
  }
}
