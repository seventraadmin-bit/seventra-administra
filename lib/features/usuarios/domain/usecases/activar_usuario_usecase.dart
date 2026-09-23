import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/usuario_repository.dart';

sealed class ActivarUsuarioResultado {}

class ActivarUsuarioExitoso extends ActivarUsuarioResultado {
  ActivarUsuarioExitoso(this.usuario);
  final UsuarioData usuario;
}

class ActivarUsuarioNoExiste extends ActivarUsuarioResultado {}

class ActivarUsuarioYaActivo extends ActivarUsuarioResultado {}

/// Etapa 3B — la cuenta pertenece a una persona que sigue de baja.
///
/// Reactivarla devolvería el acceso que la baja acaba de retirar, y la
/// reactivación es precisamente la acción rutinaria en la que eso pasa
/// sin que nadie lo note. El camino correcto existe y es el de negocio:
/// registrar el reingreso en Personal —que no crea una persona nueva,
/// sino un periodo nuevo sobre la misma— y entonces reactivar.
///
/// No aplica a una cuenta independiente: sin Empleado detrás no hay
/// estado laboral que contradecir.
class ActivarUsuarioEmpleadoDeBaja extends ActivarUsuarioResultado {
  ActivarUsuarioEmpleadoDeBaja(this.nombreEmpleado);
  final String nombreEmpleado;
}

class ActivarUsuarioErrorInesperado extends ActivarUsuarioResultado {
  ActivarUsuarioErrorInesperado(this.mensaje);
  final String mensaje;
}

class ActivarUsuarioUseCase {
  ActivarUsuarioUseCase(this._usuarioRepository);

  final UsuarioRepository _usuarioRepository;

  Future<ActivarUsuarioResultado> ejecutar({required String usuarioId, String? actorUsuarioId}) async {
    try {
      final actual = await _usuarioRepository.obtenerConIdentidad(usuarioId);
      if (actual == null) return ActivarUsuarioNoExiste();
      if (actual.cuentaActiva) return ActivarUsuarioYaActivo();
      if (actual.empleadoDeBaja) return ActivarUsuarioEmpleadoDeBaja(actual.nombreEfectivo);

      final usuario = await _usuarioRepository.activar(usuarioId: usuarioId, actorUsuarioId: actorUsuarioId);
      return ActivarUsuarioExitoso(usuario);
    } catch (e) {
      return ActivarUsuarioErrorInesperado(e.toString());
    }
  }
}
