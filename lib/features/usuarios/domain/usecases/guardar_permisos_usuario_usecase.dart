import 'package:riseg_one/core/permissions/modulos_permiso.dart';

import '../repositories/permiso_usuario_repository.dart';
import '../repositories/usuario_repository.dart';

sealed class GuardarPermisosUsuarioResultado {}

class GuardarPermisosUsuarioExitoso extends GuardarPermisosUsuarioResultado {
  GuardarPermisosUsuarioExitoso(this.codigos);
  final Set<String> codigos;
}

class GuardarPermisosUsuarioNoExiste extends GuardarPermisosUsuarioResultado {}

/// No se pueden guardar permisos individuales para un Maestro — los
/// suyos se calculan siempre en memoria (ver `modulos_permiso.dart`),
/// nunca se persisten como filas de `PermisoUsuario`.
class GuardarPermisosUsuarioEsMaestro extends GuardarPermisosUsuarioResultado {}

class GuardarPermisosUsuarioErrorInesperado extends GuardarPermisosUsuarioResultado {
  GuardarPermisosUsuarioErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Guarda el conjunto completo de permisos de un Usuario (Etapa 11B).
///
/// Aplica `normalizarPermisos` como red de seguridad final (nunca
/// persiste `crear=true, ver=false` aunque la UI tuviera un bug — ver
/// su doc comment) y descarta cualquier código que no exista en el
/// catálogo (`modulosPermiso`), para que un valor corrupto/obsoleto
/// nunca quede guardado.
class GuardarPermisosUsuarioUseCase {
  GuardarPermisosUsuarioUseCase(this._usuarioRepository, this._permisoUsuarioRepository);

  final UsuarioRepository _usuarioRepository;
  final PermisoUsuarioRepository _permisoUsuarioRepository;

  Future<GuardarPermisosUsuarioResultado> ejecutar({
    required String usuarioId,
    required Set<String> codigos,
    String? actorUsuarioId,
  }) async {
    try {
      final usuario = await _usuarioRepository.obtenerPorId(usuarioId);
      if (usuario == null) return GuardarPermisosUsuarioNoExiste();
      if (usuario.esMaestro) return GuardarPermisosUsuarioEsMaestro();

      final codigosValidos = todosLosCodigosDePermiso();
      final filtrados = codigos.where(codigosValidos.contains).toSet();
      final normalizados = normalizarPermisos(filtrados);

      await _permisoUsuarioRepository.guardar(
        usuarioId: usuarioId,
        codigos: normalizados,
        actorUsuarioId: actorUsuarioId,
      );
      return GuardarPermisosUsuarioExitoso(normalizados);
    } catch (e) {
      return GuardarPermisosUsuarioErrorInesperado(e.toString());
    }
  }
}
