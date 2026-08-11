import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/usuario_repository.dart';

sealed class ActivarUsuarioResultado {}

class ActivarUsuarioExitoso extends ActivarUsuarioResultado {
  ActivarUsuarioExitoso(this.usuario);
  final UsuarioData usuario;
}

class ActivarUsuarioNoExiste extends ActivarUsuarioResultado {}

class ActivarUsuarioYaActivo extends ActivarUsuarioResultado {}

class ActivarUsuarioErrorInesperado extends ActivarUsuarioResultado {
  ActivarUsuarioErrorInesperado(this.mensaje);
  final String mensaje;
}

class ActivarUsuarioUseCase {
  ActivarUsuarioUseCase(this._usuarioRepository);

  final UsuarioRepository _usuarioRepository;

  Future<ActivarUsuarioResultado> ejecutar({required String usuarioId, String? actorUsuarioId}) async {
    try {
      final actual = await _usuarioRepository.obtenerPorId(usuarioId);
      if (actual == null) return ActivarUsuarioNoExiste();
      if (actual.cicloVidaRegistro == 'activo') return ActivarUsuarioYaActivo();

      final usuario = await _usuarioRepository.activar(usuarioId: usuarioId, actorUsuarioId: actorUsuarioId);
      return ActivarUsuarioExitoso(usuario);
    } catch (e) {
      return ActivarUsuarioErrorInesperado(e.toString());
    }
  }
}
