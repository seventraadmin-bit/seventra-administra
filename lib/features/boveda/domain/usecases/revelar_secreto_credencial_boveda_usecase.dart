import 'package:riseg_one/core/security/credential_cipher.dart';

import '../repositories/boveda_credencial_repository.dart';

/// Qué acción del usuario disparó la revelación — cada una registra su
/// propio `tipoEvento` (mismo criterio que Telefonía Etapa 9D: mostrar
/// o copiar un secreto es una acción auditable por separado, nunca una
/// sola "reveló").
enum AccionRevelacionSecreto { mostrar, copiar }

sealed class RevelarSecretoCredencialBovedaResultado {}

class RevelarSecretoCredencialBovedaExitoso extends RevelarSecretoCredencialBovedaResultado {
  RevelarSecretoCredencialBovedaExitoso(this.secreto);

  /// Texto plano, transitorio — solo vive en memoria el tiempo que la
  /// UI lo necesite; nunca se persiste ni se registra en el evento de
  /// auditoría.
  final String secreto;
}

class RevelarSecretoCredencialBovedaSinSecreto extends RevelarSecretoCredencialBovedaResultado {}

class RevelarSecretoCredencialBovedaErrorInesperado extends RevelarSecretoCredencialBovedaResultado {
  RevelarSecretoCredencialBovedaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Descifra el secreto vigente de una credencial de la Bóveda para
/// mostrarlo o copiarlo (Etapa 14D) — clon 1:1 de
/// `RevelarCredencialEquipoTelefonicoUseCase` (Etapa 9D). Cada llamada
/// (mostrar o copiar) descifra de nuevo y registra su propio evento —
/// nunca se reutiliza un texto plano ya descifrado entre las dos
/// acciones, para minimizar cuánto tiempo vive el secreto en memoria.
/// Autorización exclusivamente vía `exigirMaestro` en
/// `boveda_providers.dart` — la Bóveda entera es Maestro-only, sin
/// permiso dinámico independiente para revelar (a diferencia de
/// Telefonía, que sí distingue `telefonia.ver` de
/// `telefonia.verCredenciales`).
class RevelarSecretoCredencialBovedaUseCase {
  RevelarSecretoCredencialBovedaUseCase(this._repository, this._cipher);

  final BovedaCredencialRepository _repository;
  final CredentialCipher _cipher;

  Future<RevelarSecretoCredencialBovedaResultado> ejecutar({
    required String credencialId,
    required AccionRevelacionSecreto accion,
    String? actorUsuarioId,
  }) async {
    final credencial = await _repository.obtenerPorId(credencialId);
    final cifrado = credencial?.secretoCifrado;
    if (cifrado == null) return RevelarSecretoCredencialBovedaSinSecreto();

    try {
      final secreto = await _cipher.descifrar(cifrado);
      final tipoEvento = switch (accion) {
        AccionRevelacionSecreto.mostrar => 'secretoRevelado',
        AccionRevelacionSecreto.copiar => 'secretoCopiado',
      };
      await _repository.registrarEvento(credencialId: credencialId, tipoEvento: tipoEvento, actorUsuarioId: actorUsuarioId);
      return RevelarSecretoCredencialBovedaExitoso(secreto);
    } catch (e) {
      return RevelarSecretoCredencialBovedaErrorInesperado(e.toString());
    }
  }
}
