import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show puestoRepositoryProvider;
import 'package:riseg_one/features/personal/personal_providers.dart' show empleadoRepositoryProvider;

import '../domain/usecases/activar_usuario_usecase.dart';
import '../domain/usecases/cambiar_contrasena_usuario_usecase.dart';
import '../domain/usecases/corregir_usuario_usecase.dart';
import '../domain/usecases/crear_usuario_usecase.dart';
import '../domain/usecases/desactivar_usuario_usecase.dart';
import '../domain/usecases/guardar_permisos_usuario_usecase.dart';
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

  /// Empleados activos que pueden vincularse a una cuenta nueva
  /// (Etapa "Usuarios, permisos y UX de seguridad") — se excluyen los
  /// que YA tienen cuenta: una persona no debe terminar con dos.
  Future<List<EmpleadoData>> empleadosVinculables() async {
    final activos = await ref.read(empleadoRepositoryProvider).listar(estatus: 'activo');
    final yaConCuenta = {
      for (final u in await ref.read(usuarioRepositoryProvider).listar())
        if (u.empleadoId != null) u.empleadoId!,
    };
    return activos.where((e) => !yaConCuenta.contains(e.id)).toList();
  }

  Future<CrearUsuarioResultado> crear({
    required String nombre,
    required String nombreUsuario,
    required String password,
    required String puestoId,
    String? empleadoId,
    bool esMaestro = false,
    Set<String> permisosIniciales = const {},
  }) async {
    // Crear una cuenta MAESTRA no es administrar usuarios: es repartir
    // acceso total, presente y futuro. Solo un Maestro puede hacerlo
    // (Etapa "Usuarios, permisos y UX de seguridad") — sin este candado,
    // cualquiera con `usuarios.administrar` se fabricaba una cuenta
    // Maestra y entraba con ella.
    if (esMaestro && !ref.read(permissionServiceProvider).esMaestroActivo) {
      return CrearUsuarioErrorInesperado('Crear una cuenta Maestra requiere el Usuario Maestro.');
    }

    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'usuarios.administrar',
      () => ref.read(crearUsuarioUseCaseProvider).ejecutar(
            nombre: nombre,
            nombreUsuario: nombreUsuario,
            password: password,
            puestoId: puestoId,
            empleadoId: empleadoId,
            esMaestro: esMaestro,
            permisosIniciales: permisosIniciales,
            actorUsuarioId: _actorUsuarioId,
          ),
      CrearUsuarioErrorInesperado.new,
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
    // ELEVAR una cuenta a Maestra exige ser Maestro — incluida la
    // propia. `usuarios.administrar` alcanza para corregir nombre,
    // nombre de usuario y puesto; nunca para repartir acceso total.
    // Quitar el Maestro no necesita este candado: ya está protegido
    // contra dejar al sistema sin ninguno
    // (`CorregirUsuarioBloqueadaPorUltimoMaestro`), y degradar no
    // amplía acceso.
    final permisos = ref.read(permissionServiceProvider);
    if (esMaestro && !permisos.esMaestroActivo) {
      final actual = await ref.read(usuarioRepositoryProvider).obtenerPorId(usuarioId);
      if (actual == null || !actual.esMaestro) {
        return CorregirUsuarioErrorInesperado('Otorgar la cuenta Maestra requiere el Usuario Maestro.');
      }
    }

    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'usuarios.administrar',
      () => ref.read(corregirUsuarioUseCaseProvider).ejecutar(
            usuarioId: usuarioId,
            nombre: nombre,
            nombreUsuario: nombreUsuario,
            puestoId: puestoId,
            esMaestro: esMaestro,
            actorUsuarioId: _actorUsuarioId,
          ),
      CorregirUsuarioErrorInesperado.new,
    );
    if (resultado is CorregirUsuarioExitoso) await _cargar();
    return resultado;
  }

  Future<CambiarContrasenaUsuarioResultado> cambiarContrasena({required String usuarioId, required String password}) async {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      // Restablecer la contraseña de OTRA cuenta es su propia facultad.
      'usuarios.resetearPassword',
      () => ref.read(cambiarContrasenaUsuarioUseCaseProvider).ejecutar(
            usuarioId: usuarioId,
            password: password,
            actorUsuarioId: _actorUsuarioId,
            // Un reseteo deja una contraseña que conoce quien la fijó:
            // la cuenta queda obligada a cambiarla en su próximo acceso.
            exigirCambio: true,
          ),
      CambiarContrasenaUsuarioErrorInesperado.new,
    );
  }

  Future<ActivarUsuarioResultado> activar(String usuarioId) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'usuarios.administrar',
      () => ref.read(activarUsuarioUseCaseProvider).ejecutar(usuarioId: usuarioId, actorUsuarioId: _actorUsuarioId),
      ActivarUsuarioErrorInesperado.new,
    );
    if (resultado is ActivarUsuarioExitoso) await _cargar();
    return resultado;
  }

  Future<DesactivarUsuarioResultado> desactivar({required String usuarioId, required String motivo}) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'usuarios.administrar',
      () => ref
          .read(desactivarUsuarioUseCaseProvider)
          .ejecutar(usuarioId: usuarioId, actorUsuarioId: _actorUsuarioId, motivo: motivo),
      DesactivarUsuarioErrorInesperado.new,
    );
    if (resultado is DesactivarUsuarioExitoso) await _cargar();
    return resultado;
  }

  Future<Set<String>> obtenerPermisos(String usuarioId) {
    return ref.read(permisoUsuarioRepositoryProvider).obtenerCodigos(usuarioId);
  }

  Future<GuardarPermisosUsuarioResultado> guardarPermisos({required String usuarioId, required Set<String> codigos}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      // Etapa "Usuarios, permisos y UX de seguridad": otorgar permisos
      // se separa de administrar cuentas — es la facultad con la que
      // alguien podría ampliar el alcance de una cuenta, la propia
      // incluida.
      'usuarios.otorgarPermisos',
      () => ref.read(guardarPermisosUsuarioUseCaseProvider).ejecutar(
            usuarioId: usuarioId,
            codigos: codigos,
            actorUsuarioId: _actorUsuarioId,
          ),
      GuardarPermisosUsuarioErrorInesperado.new,
    );
  }
}
