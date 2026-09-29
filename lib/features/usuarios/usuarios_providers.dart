import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/auth/password_hasher.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/core/permissions/permission_service.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show puestoRepositoryProvider;
import 'package:riseg_one/features/personal/personal_providers.dart' show empleadoRepositoryProvider;

import 'data/repositories/auditoria_repository_impl.dart';
import 'data/repositories/permiso_usuario_repository_impl.dart';
import 'data/repositories/usuario_repository_impl.dart';
import 'domain/repositories/auditoria_repository.dart';
import 'domain/repositories/permiso_usuario_repository.dart';
import 'domain/repositories/usuario_repository.dart';
import 'domain/sesion_usuario.dart';
import 'domain/usecases/activar_usuario_usecase.dart';
import 'domain/usecases/buscar_auditoria_usecase.dart';
import 'domain/usecases/cambiar_contrasena_usuario_usecase.dart';
import 'domain/usecases/cambiar_vinculo_empleado_usecase.dart';
import 'domain/usecases/corregir_usuario_usecase.dart';
import 'domain/usecases/crear_usuario_usecase.dart';
import 'domain/usecases/desactivar_usuario_usecase.dart';
import 'domain/usecases/guardar_permisos_usuario_usecase.dart';
import 'presentation/sesion_controller.dart';

final passwordHasherProvider = Provider<PasswordHasher>((ref) => const PasswordHasher());

final usuarioRepositoryProvider = Provider<UsuarioRepository>((ref) {
  return UsuarioRepositoryImpl(ref.watch(appDatabaseProvider));
});

final permisoUsuarioRepositoryProvider = Provider<PermisoUsuarioRepository>((ref) {
  return PermisoUsuarioRepositoryImpl(ref.watch(appDatabaseProvider));
});

/// Implementación real de `PermissionService` (Etapa 11B) — reemplaza
/// el scaffold inerte que existía desde antes de la Etapa 11. Ligada a
/// `sesionControllerProvider`: sin sesión niega todo, un Maestro
/// concede todo sin tener filas de `PermisoUsuario`, cualquier otro
/// usuario se resuelve contra los permisos de su sesión, que desde la
/// Etapa 3B se revalidan contra la base en cada navegación (ver
/// `SesionController.revalidar`).
class SessionPermissionService implements PermissionService {
  const SessionPermissionService(this._sesion, {Future<SesionUsuario?> Function()? revalidar})
    : _revalidar = revalidar;

  final SesionUsuario? _sesion;

  /// Vuelve a preguntarle a la base quién es esta cuenta y devuelve la
  /// sesión resultante (`null` si dejó de ser válida). Opcional porque
  /// un servicio construido a mano —en una prueba de unidad, sin base
  /// detrás— no tiene a quién preguntarle.
  final Future<SesionUsuario?> Function()? _revalidar;

  @override
  bool hasCode(String codigo) {
    final sesion = _sesion;
    if (sesion == null) return false;
    if (sesion.esMaestro) return true;
    return sesion.permisos.contains(codigo);
  }

  @override
  bool hasPermission(String modulo, String accion) => hasCode('$modulo.$accion');

  @override
  bool get esMaestroActivo => _sesion?.esMaestro ?? false;

  @override
  bool get puedeOperar => _sesion != null;

  /// Se lee del `CompanyContext`, no de ninguna tabla local: la suscripción es
  /// un hecho de la Organization y sólo el servidor lo sabe.
  @override
  bool get restringido => _sesion?.restringido ?? false;

  @override
  Future<PermissionService> vigente() async {
    final revalidar = _revalidar;
    if (revalidar == null) return this;
    // Una sesión que dejó de ser válida vuelve como `null`, y un
    // servicio sin sesión niega absolutamente todo: fail closed sin
    // ninguna rama especial.
    return SessionPermissionService(await revalidar(), revalidar: revalidar);
  }
}

final permissionServiceProvider = Provider<PermissionService>((ref) {
  // El notificador se captura AQUÍ, no dentro de la función: revalidar
  // cambia la sesión, y eso marca a este provider como obsoleto — usar
  // su `ref` después de ese instante es un error en tiempo de
  // ejecución. `sesionControllerProvider` es `keepAlive`, así que la
  // instancia es estable y la referencia sigue siendo válida.
  final sesion = ref.read(sesionControllerProvider.notifier);
  return SessionPermissionService(
    ref.watch(sesionControllerProvider),
    // La revalidación vive aquí y no dentro del servicio para que
    // `SessionPermissionService` siga sin conocer Riverpod ni la base:
    // recibe una función y no le importa de dónde sale la respuesta.
    revalidar: sesion.revalidar,
  );
});

/// Punto único de autorización (Etapa 11C) — cualquier Controller que
/// proteja una acción escribe (`ref.read(authorizationServiceProvider)
/// .verificar('modulo.accion')`) en vez de leer `permissionServiceProvider`
/// directo, para que la lógica de "cómo se autoriza" quede en un solo
/// lugar. Ver el doc comment de `AuthorizationService`.
final authorizationServiceProvider = Provider<AuthorizationService>((ref) {
  return AuthorizationService(ref.watch(permissionServiceProvider));
});

final crearUsuarioUseCaseProvider = Provider<CrearUsuarioUseCase>((ref) {
  return CrearUsuarioUseCase(
    ref.watch(usuarioRepositoryProvider),
    ref.watch(puestoRepositoryProvider),
    ref.watch(passwordHasherProvider),
    // Etapa 3B: el Empleado se valida de verdad (existe, activo, sin
    // otra cuenta) — el desplegable no cuenta como validación.
    ref.watch(empleadoRepositoryProvider),
  );
});

/// Vincular/re-vincular/desvincular una cuenta de un Empleado (Etapa
/// 3B) — gateado con `usuarios.administrar` en `UsuariosController`.
final cambiarVinculoEmpleadoUseCaseProvider = Provider<CambiarVinculoEmpleadoUseCase>((ref) {
  return CambiarVinculoEmpleadoUseCase(ref.watch(usuarioRepositoryProvider), ref.watch(empleadoRepositoryProvider));
});

final corregirUsuarioUseCaseProvider = Provider<CorregirUsuarioUseCase>((ref) {
  return CorregirUsuarioUseCase(ref.watch(usuarioRepositoryProvider), ref.watch(puestoRepositoryProvider));
});

/// RESETEAR la contraseña de OTRA cuenta — gateado con
/// `usuarios.resetearPassword` en `UsuariosController.cambiarContrasena`.
final cambiarContrasenaUsuarioUseCaseProvider = Provider<CambiarContrasenaUsuarioUseCase>((ref) {
  return CambiarContrasenaUsuarioUseCase(ref.watch(usuarioRepositoryProvider), ref.watch(passwordHasherProvider));
});

/// Cambiar la PROPIA contraseña — provider DISTINTO a propósito, aunque
/// comparta la clase del caso de uso (Etapa "Usuarios, permisos y UX de
/// seguridad").
///
/// Son dos operaciones diferentes con autorizaciones diferentes:
/// resetear la contraseña de otra persona exige
/// `usuarios.resetearPassword`; cambiar la propia no exige ningún
/// permiso, porque la autorización es la sesión misma y solo puede
/// afectar a la cuenta autenticada. Exigir el permiso de administración
/// dejaría a todo usuario Normal sin poder cambiar su contraseña.
///
/// Separarlos también evita que el auditor de providers crudos vea una
/// vía sin autorizar hacia un provider protegido: no es la misma vía,
/// es otra operación. Ver `cambiarMiContrasenaProvider`.
final cambiarMiContrasenaUseCaseProvider = Provider<CambiarContrasenaUsuarioUseCase>((ref) {
  return CambiarContrasenaUsuarioUseCase(ref.watch(usuarioRepositoryProvider), ref.watch(passwordHasherProvider));
});

final activarUsuarioUseCaseProvider = Provider<ActivarUsuarioUseCase>((ref) {
  return ActivarUsuarioUseCase(ref.watch(usuarioRepositoryProvider));
});

final desactivarUsuarioUseCaseProvider = Provider<DesactivarUsuarioUseCase>((ref) {
  return DesactivarUsuarioUseCase(ref.watch(usuarioRepositoryProvider));
});

final guardarPermisosUsuarioUseCaseProvider = Provider<GuardarPermisosUsuarioUseCase>((ref) {
  return GuardarPermisosUsuarioUseCase(ref.watch(usuarioRepositoryProvider), ref.watch(permisoUsuarioRepositoryProvider));
});

/// Auditoría central (Etapa 11D) — solo lectura, agrega los ~17
/// orígenes de eventos del proyecto. Ver el doc comment de
/// `AuditoriaRepositoryImpl`.
final auditoriaRepositoryProvider = Provider<AuditoriaRepository>((ref) {
  return AuditoriaRepositoryImpl(ref.watch(appDatabaseProvider));
});

final buscarAuditoriaUseCaseProvider = Provider<BuscarAuditoriaUseCase>((ref) {
  return BuscarAuditoriaUseCase(ref.watch(auditoriaRepositoryProvider));
});
