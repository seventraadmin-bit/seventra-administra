import 'package:riseg_one/core/auth/password_hasher.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/permissions/modulos_permiso.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/puesto_repository.dart';

import '../repositories/usuario_repository.dart';

sealed class CrearUsuarioResultado {}

class CrearUsuarioExitoso extends CrearUsuarioResultado {
  CrearUsuarioExitoso(this.usuario);
  final UsuarioData usuario;
}

class CrearUsuarioNombreRequerido extends CrearUsuarioResultado {}

class CrearUsuarioNombreUsuarioRequerido extends CrearUsuarioResultado {}

class CrearUsuarioNombreUsuarioDuplicado extends CrearUsuarioResultado {}

/// Mínimo 8 caracteres — sin exigir símbolos/mayúsculas por ahora, es
/// una app interna sin recuperación por correo todavía (ver el plan de
/// la Etapa 11A).
class CrearUsuarioContrasenaInvalida extends CrearUsuarioResultado {}

class CrearUsuarioPuestoInvalido extends CrearUsuarioResultado {}

class CrearUsuarioErrorInesperado extends CrearUsuarioResultado {
  CrearUsuarioErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Da de alta un Usuario (Etapa 11A) — valida unicidad de
/// `nombreUsuario`, longitud mínima de contraseña y que el Puesto
/// capturado exista/esté activo (descriptivo, nunca de seguridad — ver
/// el doc comment de `Puesto`), hashea la contraseña y delega a
/// `UsuarioRepository.crear`.
class CrearUsuarioUseCase {
  CrearUsuarioUseCase(this._usuarioRepository, this._puestoRepository, this._passwordHasher);

  final UsuarioRepository _usuarioRepository;
  final PuestoRepository _puestoRepository;
  final PasswordHasher _passwordHasher;

  static const _longitudMinimaContrasena = 8;

  Future<CrearUsuarioResultado> ejecutar({
    required String nombre,
    required String nombreUsuario,
    required String password,
    required String puestoId,
    String? empleadoId,
    bool esMaestro = false,
    Set<String> permisosIniciales = const {},
    String? actorUsuarioId,
  }) async {
    final nombreLimpio = nombre.trim();
    if (nombreLimpio.isEmpty) return CrearUsuarioNombreRequerido();

    final nombreUsuarioLimpio = nombreUsuario.trim();
    if (nombreUsuarioLimpio.isEmpty) return CrearUsuarioNombreUsuarioRequerido();

    if (password.length < _longitudMinimaContrasena) return CrearUsuarioContrasenaInvalida();

    try {
      final existente = await _usuarioRepository.obtenerPorNombreUsuario(nombreUsuarioLimpio);
      if (existente != null) return CrearUsuarioNombreUsuarioDuplicado();

      final puesto = await _puestoRepository.obtenerPorId(puestoId);
      if (puesto == null || puesto.cicloVidaRegistro != 'activo') return CrearUsuarioPuestoInvalido();

      final usuario = await _usuarioRepository.crear(
        nombre: nombreLimpio,
        nombreUsuario: nombreUsuarioLimpio,
        passwordHash: _passwordHasher.hash(password),
        puestoId: puestoId,
        empleadoId: empleadoId,
        esMaestro: esMaestro,
        // Toda cuenta creada por un Maestro nace con contraseña
        // TEMPORAL: su titular debe cambiarla antes de poder usar el
        // sistema. El primer Maestro del bootstrap no pasa por aquí.
        debeCambiarPassword: true,
        permisosIniciales: esMaestro ? const {} : normalizarPermisos(permisosIniciales),
        actorUsuarioId: actorUsuarioId,
      );
      return CrearUsuarioExitoso(usuario);
    } catch (e) {
      return CrearUsuarioErrorInesperado(e.toString());
    }
  }
}
