import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/security/credential_cipher.dart';

import '../repositories/boveda_credencial_repository.dart';

sealed class CrearCredencialBovedaResultado {}

class CrearCredencialBovedaExitoso extends CrearCredencialBovedaResultado {
  CrearCredencialBovedaExitoso(this.credencial);
  final BovedaCredencialData credencial;
}

class CrearCredencialBovedaNombreRequerido extends CrearCredencialBovedaResultado {}

class CrearCredencialBovedaErrorInesperado extends CrearCredencialBovedaResultado {
  CrearCredencialBovedaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Alta de una credencial de la Bóveda (Etapa 14D) — `nombre`/`tipo`
/// siempre obligatorios, el resto de los campos opcionales. Si viene
/// `secreto` en texto plano, se cifra aquí antes de persistir (nunca en
/// el repositorio) — mismo criterio que `CambiarContrasenaEquipoTelefonicoUseCase`
/// (Etapa 9D).
class CrearCredencialBovedaUseCase {
  CrearCredencialBovedaUseCase(this._repository, this._cipher);

  final BovedaCredencialRepository _repository;
  final CredentialCipher _cipher;

  Future<CrearCredencialBovedaResultado> ejecutar({
    required String nombre,
    required String tipo,
    String? usuarioAcceso,
    String? correo,
    String? secreto,
    String? url,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    final nombreLimpio = nombre.trim();
    if (nombreLimpio.isEmpty) return CrearCredencialBovedaNombreRequerido();

    try {
      String? secretoCifrado;
      DateTime? fechaSecreto;
      if (secreto != null && secreto.isNotEmpty) {
        secretoCifrado = await _cipher.cifrar(secreto);
        fechaSecreto = DateTime.now();
      }

      final credencial = await _repository.crear(
        nombre: nombreLimpio,
        tipo: tipo,
        usuarioAcceso: usuarioAcceso,
        correo: correo,
        secretoCifrado: secretoCifrado,
        fechaActualizacionSecreto: fechaSecreto,
        url: url,
        observaciones: observaciones,
      );
      await _repository.registrarEvento(credencialId: credencial.id, tipoEvento: 'creada', actorUsuarioId: actorUsuarioId);
      return CrearCredencialBovedaExitoso(credencial);
    } catch (e) {
      return CrearCredencialBovedaErrorInesperado(e.toString());
    }
  }
}
