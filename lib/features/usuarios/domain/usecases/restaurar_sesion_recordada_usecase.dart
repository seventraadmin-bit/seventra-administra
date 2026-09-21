import 'package:riseg_one/core/auth/sesion_recordada_almacen.dart';
import 'package:riseg_one/core/permissions/modulos_permiso.dart';

import '../repositories/permiso_usuario_repository.dart';
import '../repositories/usuario_repository.dart';
import '../sesion_usuario.dart';

/// Resuelve "Recuérdame en este equipo" al arrancar la aplicación
/// (Etapa 15) — se ejecuta desde `bootstrap()`, **antes** de `runApp`,
/// para que el estado inicial de `sesionControllerProvider` ya venga
/// resuelto (el `redirect` del router lee la sesión de forma síncrona,
/// nunca espera un `Future`).
///
/// `null` si no hay token, si no corresponde a ninguna fila, o si el
/// Usuario ya no existe / no está activo — en cualquiera de esos casos
/// se limpia el Almacén y la fila de `SesionPersistente`, así nunca
/// queda un rastro apuntando a algo inválido (incluido el caso de
/// restaurar un respaldo de la Etapa 14C con un Usuario distinto).
class RestaurarSesionRecordadaUseCase {
  RestaurarSesionRecordadaUseCase(this._usuarioRepository, this._permisoUsuarioRepository, [AlmacenSesionRecordada? almacenSesion])
      : _almacenSesion = almacenSesion ?? const AlmacenSesionRecordadaWindows();

  final UsuarioRepository _usuarioRepository;
  final PermisoUsuarioRepository _permisoUsuarioRepository;
  final AlmacenSesionRecordada _almacenSesion;

  Future<SesionUsuario?> ejecutar() async {
    final token = await _almacenSesion.leer();
    if (token == null) return null;

    final usuario = await _usuarioRepository.obtenerPorTokenSesionHash(hashTokenSesion(token));
    if (usuario == null || usuario.cicloVidaRegistro != 'activo') {
      await _almacenSesion.borrar();
      if (usuario != null) await _usuarioRepository.borrarSesionPersistente(usuario.id);
      return null;
    }

    final permisos =
        usuario.esMaestro ? todosLosCodigosDePermiso() : await _permisoUsuarioRepository.obtenerCodigos(usuario.id);

    return SesionUsuario(
      usuarioId: usuario.id,
      nombre: usuario.nombre,
      nombreUsuario: usuario.nombreUsuario,
      esMaestro: usuario.esMaestro,
      permisos: permisos,
      debeCambiarPassword: usuario.debeCambiarPassword,
    );
  }
}
