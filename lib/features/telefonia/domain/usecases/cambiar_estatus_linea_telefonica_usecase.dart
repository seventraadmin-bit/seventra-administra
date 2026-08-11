import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/linea_telefonica_repository.dart';

sealed class CambiarEstatusLineaTelefonicaResultado {}

class CambiarEstatusLineaTelefonicaExitoso extends CambiarEstatusLineaTelefonicaResultado {
  CambiarEstatusLineaTelefonicaExitoso(this.linea);
  final LineaTelefonicaData linea;
}

class CambiarEstatusLineaTelefonicaNoExiste extends CambiarEstatusLineaTelefonicaResultado {}

/// El destino no es uno manual válido (`baja` usa
/// `DarDeBajaLineaTelefonicaUseCase`).
class CambiarEstatusLineaTelefonicaDestinoInvalido extends CambiarEstatusLineaTelefonicaResultado {}

class CambiarEstatusLineaTelefonicaYaDeBaja extends CambiarEstatusLineaTelefonicaResultado {}

class CambiarEstatusLineaTelefonicaErrorInesperado extends CambiarEstatusLineaTelefonicaResultado {
  CambiarEstatusLineaTelefonicaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cambia manualmente el estatus entre `activa`/`suspendida` (Etapa
/// 9A) — nunca hacia `baja` (terminal, ver `DarDeBajaLineaTelefonicaUseCase`).
/// Una línea dada de baja nunca vuelve a cambiar de estatus (sin ciclo
/// de reingreso en este dominio, ver el doc comment de `LineaTelefonica`).
class CambiarEstatusLineaTelefonicaUseCase {
  CambiarEstatusLineaTelefonicaUseCase(this._repository);

  final LineaTelefonicaRepository _repository;

  static const _destinosValidos = {'activa', 'suspendida'};

  Future<CambiarEstatusLineaTelefonicaResultado> ejecutar({
    required String lineaTelefonicaId,
    required String estatus,
  }) async {
    if (!_destinosValidos.contains(estatus)) return CambiarEstatusLineaTelefonicaDestinoInvalido();

    final linea = await _repository.obtenerPorId(lineaTelefonicaId);
    if (linea == null) return CambiarEstatusLineaTelefonicaNoExiste();
    if (linea.estatus == 'baja') return CambiarEstatusLineaTelefonicaYaDeBaja();

    try {
      final actualizada = await _repository.cambiarEstatus(lineaTelefonicaId: lineaTelefonicaId, estatus: estatus);
      return CambiarEstatusLineaTelefonicaExitoso(actualizada);
    } catch (e) {
      return CambiarEstatusLineaTelefonicaErrorInesperado(e.toString());
    }
  }
}
