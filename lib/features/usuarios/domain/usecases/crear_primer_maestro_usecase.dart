import 'package:riseg_one/core/auth/password_hasher.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/usuario_repository.dart';

sealed class CrearPrimerMaestroResultado {}

class CrearPrimerMaestroExitoso extends CrearPrimerMaestroResultado {
  CrearPrimerMaestroExitoso(this.usuario);
  final UsuarioData usuario;
}

/// Ya existe al menos un Usuario — el bootstrap es de una sola vez, no
/// se puede volver a ejecutar (mismo criterio que el `redirect` del
/// router, que además bloquea la ruta una vez que esto deja de ser
/// cierto).
class CrearPrimerMaestroYaExisteUnUsuario extends CrearPrimerMaestroResultado {}

class CrearPrimerMaestroNombreRequerido extends CrearPrimerMaestroResultado {}

class CrearPrimerMaestroNombreUsuarioRequerido extends CrearPrimerMaestroResultado {}

class CrearPrimerMaestroContrasenaInvalida extends CrearPrimerMaestroResultado {}

class CrearPrimerMaestroContrasenasNoCoinciden extends CrearPrimerMaestroResultado {}

class CrearPrimerMaestroErrorInesperado extends CrearPrimerMaestroResultado {
  CrearPrimerMaestroErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Crea el primer Usuario Maestro de una instalación (Etapa 11A) — sin
/// contraseña hardcodeada: la persona frente al teclado la define aquí,
/// la primera vez que la base de datos no tiene ningún Usuario. Sin
/// Puesto (ver el doc comment de `Usuario.puestoId`: en una instalación
/// recién creada el catálogo de Puestos puede estar vacío todavía).
/// Vuelve a comprobar `contarUsuarios() == 0` justo antes de escribir —
/// el `redirect` del router ya evita llegar aquí si no aplica, pero
/// esta comprobación es la que realmente protege la invariante.
class CrearPrimerMaestroUseCase {
  CrearPrimerMaestroUseCase(this._usuarioRepository, this._passwordHasher);

  final UsuarioRepository _usuarioRepository;
  final PasswordHasher _passwordHasher;

  static const _longitudMinimaContrasena = 8;

  Future<CrearPrimerMaestroResultado> ejecutar({
    required String nombre,
    required String nombreUsuario,
    required String password,
    required String confirmarPassword,
  }) async {
    final nombreLimpio = nombre.trim();
    if (nombreLimpio.isEmpty) return CrearPrimerMaestroNombreRequerido();

    final nombreUsuarioLimpio = nombreUsuario.trim();
    if (nombreUsuarioLimpio.isEmpty) return CrearPrimerMaestroNombreUsuarioRequerido();

    if (password.length < _longitudMinimaContrasena) return CrearPrimerMaestroContrasenaInvalida();
    if (password != confirmarPassword) return CrearPrimerMaestroContrasenasNoCoinciden();

    try {
      final totalUsuarios = await _usuarioRepository.contarUsuarios();
      if (totalUsuarios > 0) return CrearPrimerMaestroYaExisteUnUsuario();

      final usuario = await _usuarioRepository.crear(
        nombre: nombreLimpio,
        nombreUsuario: nombreUsuarioLimpio,
        passwordHash: _passwordHasher.hash(password),
        esMaestro: true,
        // Sin actorUsuarioId: es el único evento del sistema sin actor —
        // todavía no existe ninguna sesión. La UI lo muestra como
        // "Actor no registrado": no existe una marca en el evento que
        // permita demostrar que ESTE nulo es el bootstrap y no un actor
        // perdido, y afirmarlo por el solo hecho de ser nulo fue justo lo
        // que ocultó durante meses el hueco de Comercial.
      );
      return CrearPrimerMaestroExitoso(usuario);
    } catch (e) {
      return CrearPrimerMaestroErrorInesperado(e.toString());
    }
  }
}
