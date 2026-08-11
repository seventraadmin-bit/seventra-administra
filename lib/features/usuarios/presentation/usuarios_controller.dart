import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show puestoRepositoryProvider;

import '../domain/usecases/activar_usuario_usecase.dart';
import '../domain/usecases/cambiar_contrasena_usuario_usecase.dart';
import '../domain/usecases/corregir_usuario_usecase.dart';
import '../domain/usecases/crear_usuario_usecase.dart';
import '../domain/usecases/desactivar_usuario_usecase.dart';
import '../usuarios_providers.dart';
import 'sesion_controller.dart';
import 'usuarios_state.dart';

part 'usuarios_controller.g.dart';

/// Controlador del listado + CRUD de Usuarios (Etapa 11A) — mismo
/// molde que `ComprasController`. Cada acción de escritura pasa el
/// `usuarioId` de la sesión activa como `actorUsuarioId` — es la
/// primera vez que el proyecto tiene un actor real que registrar en un
/// evento (antes siempre llegaba `null`).
@riverpod
class UsuariosController extends _$UsuariosController {
  @override
  UsuariosState build() {
    Future.microtask(_cargar);
    return const UsuariosState();
  }

  String? get _actorUsuarioId => ref.read(sesionControllerProvider)?.usuarioId;

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, limpiarError: true);
    try {
      final usuarios = await ref.read(usuarioRepositoryProvider).listar();
      final puestos = await ref.read(puestoRepositoryProvider).listarActivos();
      state = state.copyWith(cargando: false, usuarios: usuarios, puestos: puestos, limpiarError: true);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> recargar() => _cargar();

  Future<List<UsuarioEventoData>> obtenerEventos(String usuarioId) {
    return ref.read(usuarioRepositoryProvider).listarEventos(usuarioId);
  }

  Future<CrearUsuarioResultado> crear({
    required String nombre,
    required String nombreUsuario,
    required String password,
    required String puestoId,
    bool esMaestro = false,
  }) async {
    final resultado = await ref.read(crearUsuarioUseCaseProvider).ejecutar(
          nombre: nombre,
          nombreUsuario: nombreUsuario,
          password: password,
          puestoId: puestoId,
          esMaestro: esMaestro,
          actorUsuarioId: _actorUsuarioId,
        );
    if (resultado is CrearUsuarioExitoso) await _cargar();
    return resultado;
  }

  Future<CorregirUsuarioResultado> corregir({
    required String usuarioId,
    required String nombre,
    required String nombreUsuario,
    required String puestoId,
    required bool esMaestro,
  }) async {
    final resultado = await ref.read(corregirUsuarioUseCaseProvider).ejecutar(
          usuarioId: usuarioId,
          nombre: nombre,
          nombreUsuario: nombreUsuario,
          puestoId: puestoId,
          esMaestro: esMaestro,
          actorUsuarioId: _actorUsuarioId,
        );
    if (resultado is CorregirUsuarioExitoso) await _cargar();
    return resultado;
  }

  Future<CambiarContrasenaUsuarioResultado> cambiarContrasena({required String usuarioId, required String password}) async {
    final resultado = await ref.read(cambiarContrasenaUsuarioUseCaseProvider).ejecutar(
          usuarioId: usuarioId,
          password: password,
          actorUsuarioId: _actorUsuarioId,
        );
    return resultado;
  }

  Future<ActivarUsuarioResultado> activar(String usuarioId) async {
    final resultado = await ref
        .read(activarUsuarioUseCaseProvider)
        .ejecutar(usuarioId: usuarioId, actorUsuarioId: _actorUsuarioId);
    if (resultado is ActivarUsuarioExitoso) await _cargar();
    return resultado;
  }

  Future<DesactivarUsuarioResultado> desactivar({required String usuarioId, String? motivo}) async {
    final resultado = await ref
        .read(desactivarUsuarioUseCaseProvider)
        .ejecutar(usuarioId: usuarioId, actorUsuarioId: _actorUsuarioId, motivo: motivo);
    if (resultado is DesactivarUsuarioExitoso) await _cargar();
    return resultado;
  }
}
