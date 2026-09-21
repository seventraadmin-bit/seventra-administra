import 'package:riseg_one/core/auth/password_hasher.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/usuario_repository.dart';

sealed class CambiarContrasenaUsuarioResultado {}

class CambiarContrasenaUsuarioExitoso extends CambiarContrasenaUsuarioResultado {
  CambiarContrasenaUsuarioExitoso(this.usuario);
  final UsuarioData usuario;
}

class CambiarContrasenaUsuarioNoExiste extends CambiarContrasenaUsuarioResultado {}

class CambiarContrasenaUsuarioInvalida extends CambiarContrasenaUsuarioResultado {}

class CambiarContrasenaUsuarioErrorInesperado extends CambiarContrasenaUsuarioResultado {
  CambiarContrasenaUsuarioErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cambia la contraseña de un Usuario — acción administrativa separada
/// de `CorregirUsuarioUseCase` a propósito, mismo criterio que en cada
/// dominio del proyecto ("cantidad/costo ya comprometidos no se editan
/// junto con los datos administrativos").
class CambiarContrasenaUsuarioUseCase {
  CambiarContrasenaUsuarioUseCase(this._usuarioRepository, this._passwordHasher);

  final UsuarioRepository _usuarioRepository;
  final PasswordHasher _passwordHasher;

  static const _longitudMinimaContrasena = 8;

  /// [exigirCambio]: `true` en un reseteo administrativo (la contraseña
  /// resultante la conoce quien la fijó, así que la cuenta queda
  /// obligada a cambiarla en su siguiente acceso); `false` cuando la
  /// cambia el propio titular, que es justamente cumplir esa obligación.
  Future<CambiarContrasenaUsuarioResultado> ejecutar({
    required String usuarioId,
    required String password,
    String? actorUsuarioId,
    bool exigirCambio = false,
  }) async {
    if (password.length < _longitudMinimaContrasena) return CambiarContrasenaUsuarioInvalida();

    try {
      final actual = await _usuarioRepository.obtenerPorId(usuarioId);
      if (actual == null) return CambiarContrasenaUsuarioNoExiste();

      final usuario = await _usuarioRepository.cambiarContrasena(
        usuarioId: usuarioId,
        passwordHash: _passwordHasher.hash(password),
        actorUsuarioId: actorUsuarioId,
        exigirCambio: exigirCambio,
      );
      return CambiarContrasenaUsuarioExitoso(usuario);
    } catch (e) {
      return CambiarContrasenaUsuarioErrorInesperado(e.toString());
    }
  }
}
