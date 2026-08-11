import 'package:riseg_one/core/database/app_database.dart';

/// Repositorio del dominio Usuarios (Etapa 11A). `crear`/`corregir`/
/// `cambiarContrasena`/`activar`/`desactivar` registran siempre su
/// `UsuarioEvento` correspondiente en la misma transacción — nunca hay
/// una escritura de Usuario sin su evento.
abstract interface class UsuarioRepository {
  Future<UsuarioData?> obtenerPorId(String id);

  Future<UsuarioData?> obtenerPorNombreUsuario(String nombreUsuario);

  Future<List<UsuarioData>> listar({String? cicloVidaRegistro});

  Future<int> contarUsuarios();

  /// Cuenta Maestros con `cicloVidaRegistro = activo`, excluyendo
  /// opcionalmente uno (el propio usuario que se está por corregir/
  /// desactivar) — usado para el invariante "al menos un Maestro activo".
  Future<int> contarMaestrosActivos({String? excluirUsuarioId});

  Future<List<UsuarioEventoData>> listarEventos(String usuarioId);

  Future<UsuarioData> crear({
    required String nombre,
    required String nombreUsuario,
    required String passwordHash,
    String? puestoId,
    bool esMaestro = false,
    String? actorUsuarioId,
  });

  Future<UsuarioData> corregir({
    required String usuarioId,
    String? nombre,
    String? nombreUsuario,
    String? puestoId,
    bool? esMaestro,
    String? actorUsuarioId,
    String? motivo,
  });

  Future<UsuarioData> cambiarContrasena({
    required String usuarioId,
    required String passwordHash,
    String? actorUsuarioId,
  });

  Future<UsuarioData> activar({required String usuarioId, String? actorUsuarioId});

  Future<UsuarioData> desactivar({required String usuarioId, String? actorUsuarioId, String? motivo});

  Future<UsuarioData> registrarUltimoAcceso(String usuarioId);
}
