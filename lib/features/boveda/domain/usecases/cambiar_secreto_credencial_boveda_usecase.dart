import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/security/credential_cipher.dart';

import '../repositories/boveda_credencial_repository.dart';

sealed class CambiarSecretoCredencialBovedaResultado {}

class CambiarSecretoCredencialBovedaExitoso extends CambiarSecretoCredencialBovedaResultado {
  CambiarSecretoCredencialBovedaExitoso(this.credencial);
  final BovedaCredencialData credencial;
}

class CambiarSecretoCredencialBovedaNoExiste extends CambiarSecretoCredencialBovedaResultado {}

class CambiarSecretoCredencialBovedaErrorInesperado extends CambiarSecretoCredencialBovedaResultado {
  CambiarSecretoCredencialBovedaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Única vía para tocar el secreto de una credencial de la Bóveda
/// (Etapa 14D) — cifra el nuevo valor (o lo limpia si `secreto` es
/// `null`/vacío), actualiza `fechaActualizacionSecreto` y registra el
/// evento. **Nunca conserva el valor anterior**, ni cifrado ni en el
/// evento de auditoría — mismo criterio que
/// `CambiarContrasenaEquipoTelefonicoUseCase` (Etapa 9D).
class CambiarSecretoCredencialBovedaUseCase {
  CambiarSecretoCredencialBovedaUseCase(this._repository, this._cipher);

  final BovedaCredencialRepository _repository;
  final CredentialCipher _cipher;

  Future<CambiarSecretoCredencialBovedaResultado> ejecutar({
    required String id,
    String? secreto,
    String? actorUsuarioId,
  }) async {
    try {
      final existente = await _repository.obtenerPorId(id);
      if (existente == null) return CambiarSecretoCredencialBovedaNoExiste();

      final secretoCifrado = (secreto != null && secreto.isNotEmpty) ? await _cipher.cifrar(secreto) : null;
      final actualizado = await _repository.cambiarSecreto(id: id, secretoCifrado: secretoCifrado, fecha: DateTime.now());
      await _repository.registrarEvento(credencialId: id, tipoEvento: 'secretoCambiado', actorUsuarioId: actorUsuarioId);
      return CambiarSecretoCredencialBovedaExitoso(actualizado);
    } catch (e) {
      return CambiarSecretoCredencialBovedaErrorInesperado(e.toString());
    }
  }
}
