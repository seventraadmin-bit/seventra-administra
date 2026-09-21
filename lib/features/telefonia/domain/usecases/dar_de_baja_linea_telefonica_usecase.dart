import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/linea_telefonica_table.dart' show MotivoBajaLineaTelefonica;
import '../repositories/linea_telefonica_repository.dart';

sealed class DarDeBajaLineaTelefonicaResultado {}

class DarDeBajaLineaTelefonicaExitoso extends DarDeBajaLineaTelefonicaResultado {
  DarDeBajaLineaTelefonicaExitoso(this.linea);
  final LineaTelefonicaData linea;
}

class DarDeBajaLineaTelefonicaNoExiste extends DarDeBajaLineaTelefonicaResultado {}

class DarDeBajaLineaTelefonicaYaDeBaja extends DarDeBajaLineaTelefonicaResultado {}

class DarDeBajaLineaTelefonicaObservacionesRequeridas extends DarDeBajaLineaTelefonicaResultado {}

class DarDeBajaLineaTelefonicaErrorInesperado extends DarDeBajaLineaTelefonicaResultado {
  DarDeBajaLineaTelefonicaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Baja terminal de una línea telefónica (Etapa 9A) —
/// `perdidaDelNumero`/`otro` exigen `observacionesBaja` (propiedad del
/// enum, ver el doc comment de `MotivoBajaLineaTelefonica`). Nunca borra
/// el expediente: la línea sigue siendo consultable, solo cambia de
/// estatus.
///
/// Desde la Etapa 9B, este caso de uso también cerrará la
/// `AsignacionLineaTelefonica`/`LineaTelefonicaEquipo` vigentes en la
/// misma transacción — en 9A no existen esas tablas todavía, así que no
/// hay nada que cerrar.
class DarDeBajaLineaTelefonicaUseCase {
  DarDeBajaLineaTelefonicaUseCase(this._repository);

  final LineaTelefonicaRepository _repository;

  Future<DarDeBajaLineaTelefonicaResultado> ejecutar({
    required String lineaTelefonicaId,
    required DateTime fechaBaja,
    required MotivoBajaLineaTelefonica motivoBaja,
    String? observacionesBaja,
    String? actorUsuarioId,
  }) async {
    final linea = await _repository.obtenerPorId(lineaTelefonicaId);
    if (linea == null) return DarDeBajaLineaTelefonicaNoExiste();
    if (linea.estatus == 'baja') return DarDeBajaLineaTelefonicaYaDeBaja();
    if (motivoBaja.requiereObservaciones && (observacionesBaja == null || observacionesBaja.trim().isEmpty)) {
      return DarDeBajaLineaTelefonicaObservacionesRequeridas();
    }

    try {
      final actualizada = await _repository.darDeBaja(
        lineaTelefonicaId: lineaTelefonicaId,
        fechaBaja: fechaBaja,
        motivoBaja: motivoBaja.name,
        observacionesBaja: observacionesBaja?.trim().isEmpty ?? true ? null : observacionesBaja!.trim(),
        actorUsuarioId: actorUsuarioId,
      );
      return DarDeBajaLineaTelefonicaExitoso(actualizada);
    } catch (e) {
      return DarDeBajaLineaTelefonicaErrorInesperado(e.toString());
    }
  }
}
