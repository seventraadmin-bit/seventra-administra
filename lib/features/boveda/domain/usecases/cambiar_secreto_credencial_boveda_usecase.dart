import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/security/credential_cipher.dart';

import '../repositories/boveda_credencial_repository.dart';

sealed class CambiarSecretoCredencialBovedaResultado {}

class CambiarSecretoCredencialBovedaExitoso extends CambiarSecretoCredencialBovedaResultado {
  CambiarSecretoCredencialBovedaExitoso(this.credencial);
  final BovedaCredencialData credencial;
}

class CambiarSecretoCredencialBovedaNoExiste extends CambiarSecretoCredencialBovedaResultado {}

/// La credencial está dada de baja.
///
/// Consultar la contraseña de un acceso retirado es legítimo —se guarda
/// precisamente para poder recuperarla—, pero fijarle una contraseña NUEVA
/// no significa nada: ese acceso ya no está en uso. Reactivar primero es
/// una decisión explícita, y deja su propio rastro en el historial.
///
/// La regla vive aquí, en el dominio, no en que la pantalla esconda un
/// botón: hasta ahora "dada de baja" no impedía absolutamente nada.
class CambiarSecretoCredencialBovedaDadaDeBaja extends CambiarSecretoCredencialBovedaResultado {}

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
      if (existente.cicloVidaRegistro != 'activo') {
        return CambiarSecretoCredencialBovedaDadaDeBaja();
      }

      final secretoCifrado = (secreto != null && secreto.isNotEmpty) ? await _cipher.cifrar(secreto) : null;
      final actualizado = await _repository.cambiarSecreto(
        id: id,
        secretoCifrado: secretoCifrado,
        fecha: DateTime.now(),
      );
      await _repository.registrarEvento(
        credencialId: id,
        tipoEvento: 'secretoCambiado',
        actorUsuarioId: actorUsuarioId,
      );
      return CambiarSecretoCredencialBovedaExitoso(actualizado);
    } catch (e) {
      return CambiarSecretoCredencialBovedaErrorInesperado(e.toString());
    }
  }
}
