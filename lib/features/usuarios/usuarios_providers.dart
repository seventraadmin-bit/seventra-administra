import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/auth/password_hasher.dart';
import 'package:riseg_one/core/auth/sesion_recordada_almacen.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/core/permissions/permission_service.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show puestoRepositoryProvider;

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
import 'domain/usecases/corregir_usuario_usecase.dart';
import 'domain/usecases/crear_primer_maestro_usecase.dart';
import 'domain/usecases/crear_usuario_usecase.dart';
import 'domain/usecases/desactivar_usuario_usecase.dart';
import 'domain/usecases/guardar_permisos_usuario_usecase.dart';
import 'domain/usecases/login_usecase.dart';
import 'domain/usecases/restaurar_sesion_recordada_usecase.dart';
import 'presentation/sesion_controller.dart';

final passwordHasherProvider = Provider<PasswordHasher>((ref) => const PasswordHasher());

/// "Recuérdame en este equipo" (Etapa 15) — mismo criterio que
/// `credentialCipherProvider` (Bóveda/Telefonía): una instancia propia
/// en vez de compartir la de otro módulo, aunque ambas usen
/// `flutter_secure_storage` como transporte del sistema operativo.
final almacenSesionRecordadaProvider = Provider<AlmacenSesionRecordada>((ref) => const AlmacenSesionRecordadaWindows());

final usuarioRepositoryProvider = Provider<UsuarioRepository>((ref) {
  return UsuarioRepositoryImpl(ref.watch(appDatabaseProvider));
});

final permisoUsuarioRepositoryProvider = Provider<PermisoUsuarioRepository>((ref) {
  return PermisoUsuarioRepositoryImpl(ref.watch(appDatabaseProvider));
});

/// `count(usuario)` cacheado por Riverpod — se invalida explícitamente
/// tras crear el primer Maestro (nunca vuelve a bajar a 0 después, así
/// que no hace falta refrescarlo por ningún otro motivo).
final contarUsuariosProvider = FutureProvider<int>((ref) {
  return ref.watch(usuarioRepositoryProvider).contarUsuarios();
});

/// Implementación real de `PermissionService` (Etapa 11B) — reemplaza
/// el scaffold inerte que existía desde antes de la Etapa 11. Ligada a
/// `sesionControllerProvider`: sin sesión niega todo, un Maestro
/// concede todo sin tener filas de `PermisoUsuario`, cualquier otro
/// usuario se resuelve contra los permisos ya cargados en su sesión
/// (ver el doc comment de `SesionUsuario.permisos` — no se refresca en
/// vivo, solo en el siguiente login).
class SessionPermissionService implements PermissionService {
  const SessionPermissionService(this._sesion);

  final SesionUsuario? _sesion;

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
}

final permissionServiceProvider = Provider<PermissionService>((ref) {
  return SessionPermissionService(ref.watch(sesionControllerProvider));
});

/// Punto único de autorización (Etapa 11C) — cualquier Controller que
/// proteja una acción escribe (`ref.read(authorizationServiceProvider)
/// .verificar('modulo.accion')`) en vez de leer `permissionServiceProvider`
/// directo, para que la lógica de "cómo se autoriza" quede en un solo
/// lugar. Ver el doc comment de `AuthorizationService`.
final authorizationServiceProvider = Provider<AuthorizationService>((ref) {
  return AuthorizationService(ref.watch(permissionServiceProvider));
});

final crearPrimerMaestroUseCaseProvider = Provider<CrearPrimerMaestroUseCase>((ref) {
  return CrearPrimerMaestroUseCase(ref.watch(usuarioRepositoryProvider), ref.watch(passwordHasherProvider));
});

final loginUseCaseProvider = Provider<LoginUseCase>((ref) {
  return LoginUseCase(
    ref.watch(usuarioRepositoryProvider),
    ref.watch(permisoUsuarioRepositoryProvider),
    ref.watch(passwordHasherProvider),
    ref.watch(almacenSesionRecordadaProvider),
  );
});

final restaurarSesionRecordadaUseCaseProvider = Provider<RestaurarSesionRecordadaUseCase>((ref) {
  return RestaurarSesionRecordadaUseCase(
    ref.watch(usuarioRepositoryProvider),
    ref.watch(permisoUsuarioRepositoryProvider),
    ref.watch(almacenSesionRecordadaProvider),
  );
});

final crearUsuarioUseCaseProvider = Provider<CrearUsuarioUseCase>((ref) {
  return CrearUsuarioUseCase(
    ref.watch(usuarioRepositoryProvider),
    ref.watch(puestoRepositoryProvider),
    ref.watch(passwordHasherProvider),
  );
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
