import 'package:riseg_one/core/auth/password_hasher.dart';
import 'package:riseg_one/core/permissions/modulos_permiso.dart';

import '../repositories/permiso_usuario_repository.dart';
import '../repositories/usuario_repository.dart';
import '../sesion_usuario.dart';

sealed class LoginResultado {}

class LoginExitoso extends LoginResultado {
  LoginExitoso(this.sesion);
  final SesionUsuario sesion;
}

/// Cubre tanto "el usuario no existe" como "la contraseña es
/// incorrecta" — nunca se distingue en el mensaje, para no revelar qué
/// nombres de usuario existen en el sistema.
class LoginCredencialesInvalidas extends LoginResultado {}

/// Solo se devuelve si la contraseña YA era correcta — así una cuenta
/// inactiva no se distingue de una inexistente ante quien no conoce la
/// contraseña real.
class LoginUsuarioInactivo extends LoginResultado {}

class LoginErrorInesperado extends LoginResultado {
  LoginErrorInesperado(this.mensaje);
  final String mensaje;
}

class LoginUseCase {
  LoginUseCase(this._usuarioRepository, this._permisoUsuarioRepository, this._passwordHasher);

  final UsuarioRepository _usuarioRepository;
  final PermisoUsuarioRepository _permisoUsuarioRepository;
  final PasswordHasher _passwordHasher;

  Future<LoginResultado> ejecutar({required String nombreUsuario, required String password}) async {
    try {
      final usuario = await _usuarioRepository.obtenerPorNombreUsuario(nombreUsuario.trim());
      if (usuario == null) return LoginCredencialesInvalidas();
      if (!_passwordHasher.verify(password, usuario.passwordHash)) return LoginCredencialesInvalidas();
      if (usuario.cicloVidaRegistro != 'activo') return LoginUsuarioInactivo();

      final actualizado = await _usuarioRepository.registrarUltimoAcceso(usuario.id);
      // Maestro: el catálogo completo, recalculado siempre en el
      // momento — nunca filas individuales de PermisoUsuario (ver el
      // doc comment de `SesionUsuario`/`GuardarPermisosUsuarioEsMaestro`).
      final permisos = actualizado.esMaestro
          ? todosLosCodigosDePermiso()
          : await _permisoUsuarioRepository.obtenerCodigos(actualizado.id);

      return LoginExitoso(
        SesionUsuario(
          usuarioId: actualizado.id,
          nombre: actualizado.nombre,
          nombreUsuario: actualizado.nombreUsuario,
          esMaestro: actualizado.esMaestro,
          permisos: permisos,
        ),
      );
    } catch (e) {
      return LoginErrorInesperado(e.toString());
    }
  }
}
