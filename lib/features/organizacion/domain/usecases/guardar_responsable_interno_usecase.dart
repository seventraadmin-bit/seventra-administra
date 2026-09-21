import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/servicio_repository.dart';

/// Guarda el Responsable interno de un Servicio — texto libre
/// transitorio (Personal/Usuario todavía no existen; ver el comentario
/// en `Servicio.responsableInterno`). Sin validación de dominio más
/// allá de recorte/`vacío→null` — no hay ninguna regla de negocio que
/// dependa de su contenido todavía.
class GuardarResponsableInternoUseCase {
  GuardarResponsableInternoUseCase(this._repository);

  final ServicioRepository _repository;

  Future<ServicioData> ejecutar({
    required String servicioId,
    required String? texto,
    String? actorUsuarioId,
  }) {
    final normalizado = texto?.trim();
    return _repository.guardarResponsableInterno(
      servicioId: servicioId,
      texto: (normalizado == null || normalizado.isEmpty) ? null : normalizado,
      actorUsuarioId: actorUsuarioId,
    );
  }
}
