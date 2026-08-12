import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/boveda_credencial_repository.dart';

sealed class DarDeBajaCredencialBovedaResultado {}

class DarDeBajaCredencialBovedaExitoso extends DarDeBajaCredencialBovedaResultado {
  DarDeBajaCredencialBovedaExitoso(this.credencial);
  final BovedaCredencialData credencial;
}

class DarDeBajaCredencialBovedaErrorInesperado extends DarDeBajaCredencialBovedaResultado {
  DarDeBajaCredencialBovedaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Saca una credencial de circulación (Etapa 14D) — clon del par
/// Activar/Desactivar de Área (`lib/features/organizacion/domain/usecases/
/// desactivar_area_usecase.dart`), sin regla de bloqueo por
/// dependencias: nada más en el proyecto referencia una credencial de
/// la Bóveda. Reversible en cualquier momento vía
/// `ReactivarCredencialBovedaUseCase`.
class DarDeBajaCredencialBovedaUseCase {
  DarDeBajaCredencialBovedaUseCase(this._repository);

  final BovedaCredencialRepository _repository;

  Future<DarDeBajaCredencialBovedaResultado> ejecutar({required String id, String? actorUsuarioId}) async {
    try {
      final credencial = await _repository.darDeBaja(id);
      await _repository.registrarEvento(credencialId: id, tipoEvento: 'dadaDeBaja', actorUsuarioId: actorUsuarioId);
      return DarDeBajaCredencialBovedaExitoso(credencial);
    } catch (e) {
      return DarDeBajaCredencialBovedaErrorInesperado(e.toString());
    }
  }
}
