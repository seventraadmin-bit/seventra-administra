import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/puesto_repository.dart';

import '../repositories/usuario_repository.dart';

sealed class CorregirUsuarioResultado {}

class CorregirUsuarioExitoso extends CorregirUsuarioResultado {
  CorregirUsuarioExitoso(this.usuario);
  final UsuarioData usuario;
}

class CorregirUsuarioNoExiste extends CorregirUsuarioResultado {}

class CorregirUsuarioNombreRequerido extends CorregirUsuarioResultado {}

class CorregirUsuarioNombreUsuarioRequerido extends CorregirUsuarioResultado {}

class CorregirUsuarioNombreUsuarioDuplicado extends CorregirUsuarioResultado {}

class CorregirUsuarioPuestoInvalido extends CorregirUsuarioResultado {}

/// Se intentó quitar `esMaestro` al último Maestro con
/// `cicloVidaRegistro = activo` — bloqueado sin mutar nada (mismo
/// molde que `DesactivarAreaBloqueadaPorPuestosActivos`).
class CorregirUsuarioBloqueadaPorUltimoMaestro extends CorregirUsuarioResultado {}

class CorregirUsuarioErrorInesperado extends CorregirUsuarioResultado {
  CorregirUsuarioErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige los datos administrativos de un Usuario (nombre, nombre de
/// usuario, puesto, `esMaestro`) — nunca la contraseña, que tiene su
/// propio caso de uso (`CambiarContrasenaUsuarioUseCase`).
class CorregirUsuarioUseCase {
  CorregirUsuarioUseCase(this._usuarioRepository, this._puestoRepository);

  final UsuarioRepository _usuarioRepository;
  final PuestoRepository _puestoRepository;

  Future<CorregirUsuarioResultado> ejecutar({
    required String usuarioId,
    String? nombre,
    String? nombreUsuario,
    String? puestoId,
    bool? esMaestro,
    String? actorUsuarioId,
    String? motivo,
  }) async {
    try {
      final actual = await _usuarioRepository.obtenerPorId(usuarioId);
      if (actual == null) return CorregirUsuarioNoExiste();

      String? nombreLimpio;
      if (nombre != null) {
        nombreLimpio = nombre.trim();
        if (nombreLimpio.isEmpty) return CorregirUsuarioNombreRequerido();
      }

      String? nombreUsuarioLimpio;
      if (nombreUsuario != null) {
        nombreUsuarioLimpio = nombreUsuario.trim();
        if (nombreUsuarioLimpio.isEmpty) return CorregirUsuarioNombreUsuarioRequerido();
        if (nombreUsuarioLimpio != actual.nombreUsuario) {
          final existente = await _usuarioRepository.obtenerPorNombreUsuario(nombreUsuarioLimpio);
          if (existente != null) return CorregirUsuarioNombreUsuarioDuplicado();
        }
      }

      if (puestoId != null) {
        final puesto = await _puestoRepository.obtenerPorId(puestoId);
        if (puesto == null || puesto.cicloVidaRegistro != 'activo') return CorregirUsuarioPuestoInvalido();
      }

      if (esMaestro == false && actual.esMaestro && actual.cicloVidaRegistro == 'activo') {
        final restantes = await _usuarioRepository.contarMaestrosActivos(excluirUsuarioId: usuarioId);
        if (restantes == 0) return CorregirUsuarioBloqueadaPorUltimoMaestro();
      }

      final usuario = await _usuarioRepository.corregir(
        usuarioId: usuarioId,
        nombre: nombreLimpio,
        nombreUsuario: nombreUsuarioLimpio,
        puestoId: puestoId,
        esMaestro: esMaestro,
        actorUsuarioId: actorUsuarioId,
        motivo: motivo,
      );
      return CorregirUsuarioExitoso(usuario);
    } catch (e) {
      return CorregirUsuarioErrorInesperado(e.toString());
    }
  }
}
