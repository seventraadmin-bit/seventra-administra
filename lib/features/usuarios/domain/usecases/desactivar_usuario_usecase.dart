import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/usuario_repository.dart';

sealed class DesactivarUsuarioResultado {}

class DesactivarUsuarioExitoso extends DesactivarUsuarioResultado {
  DesactivarUsuarioExitoso(this.usuario);
  final UsuarioData usuario;
}

class DesactivarUsuarioNoExiste extends DesactivarUsuarioResultado {}

class DesactivarUsuarioYaInactivo extends DesactivarUsuarioResultado {}

/// Motivo obligatorio (Etapa 11D) — desactivar una cuenta de acceso es
/// una decisión administrativa que siempre debe quedar explicada en el
/// historial (`UsuarioEvento`), a diferencia de otras correcciones
/// menores del proyecto.
class DesactivarUsuarioMotivoRequerido extends DesactivarUsuarioResultado {}

/// Se intentó desactivar al último Maestro con `cicloVidaRegistro =
/// activo` — bloqueado sin mutar nada, mismo molde que
/// `DesactivarAreaBloqueadaPorPuestosActivos`.
class DesactivarUsuarioBloqueadaPorUltimoMaestro extends DesactivarUsuarioResultado {}

class DesactivarUsuarioErrorInesperado extends DesactivarUsuarioResultado {
  DesactivarUsuarioErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Desactiva un Usuario — nunca lo elimina (pedido explícito: "no
/// borrar usuarios con historial"). El sistema nunca puede quedar sin
/// al menos un Maestro activo.
class DesactivarUsuarioUseCase {
  DesactivarUsuarioUseCase(this._usuarioRepository);

  final UsuarioRepository _usuarioRepository;

  Future<DesactivarUsuarioResultado> ejecutar({
    required String usuarioId,
    String? actorUsuarioId,
    required String motivo,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return DesactivarUsuarioMotivoRequerido();

    try {
      final actual = await _usuarioRepository.obtenerPorId(usuarioId);
      if (actual == null) return DesactivarUsuarioNoExiste();
      if (actual.cicloVidaRegistro != 'activo') return DesactivarUsuarioYaInactivo();

      if (actual.esMaestro) {
        final restantes = await _usuarioRepository.contarMaestrosActivos(excluirUsuarioId: usuarioId);
        if (restantes == 0) return DesactivarUsuarioBloqueadaPorUltimoMaestro();
      }

      final usuario = await _usuarioRepository.desactivar(
        usuarioId: usuarioId,
        actorUsuarioId: actorUsuarioId,
        motivo: motivoLimpio,
      );
      return DesactivarUsuarioExitoso(usuario);
    } catch (e) {
      return DesactivarUsuarioErrorInesperado(e.toString());
    }
  }
}
