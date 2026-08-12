import 'package:riseg_one/core/auth/password_hasher.dart';
import 'package:riseg_one/core/auth/sesion_recordada_almacen.dart';
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
  LoginUseCase(this._usuarioRepository, this._permisoUsuarioRepository, this._passwordHasher, [AlmacenSesionRecordada? almacenSesion])
      : _almacenSesion = almacenSesion ?? const AlmacenSesionRecordadaWindows();

  final UsuarioRepository _usuarioRepository;
  final PermisoUsuarioRepository _permisoUsuarioRepository;
  final PasswordHasher _passwordHasher;
  final AlmacenSesionRecordada _almacenSesion;

  /// [recordarme] (Etapa 15) — si es `true` y el login es exitoso, se
  /// genera un token aleatorio nuevo (nunca la contraseña ni un
  /// derivado de ella), se guarda su hash en `SesionPersistente` y el
  /// token en texto plano solo en el Almacén de Credenciales de Windows
  /// — ver `AlmacenSesionRecordada`.
  Future<LoginResultado> ejecutar({
    required String nombreUsuario,
    required String password,
    bool recordarme = false,
  }) async {
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

      if (recordarme) {
        final token = generarTokenSesion();
        await _usuarioRepository.crearSesionPersistente(usuarioId: actualizado.id, tokenHash: hashTokenSesion(token));
        await _almacenSesion.escribir(token);
      }

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
