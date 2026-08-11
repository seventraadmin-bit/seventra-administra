import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/auth/password_hasher.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show puestoRepositoryProvider;

import 'data/repositories/usuario_repository_impl.dart';
import 'domain/repositories/usuario_repository.dart';
import 'domain/usecases/activar_usuario_usecase.dart';
import 'domain/usecases/cambiar_contrasena_usuario_usecase.dart';
import 'domain/usecases/corregir_usuario_usecase.dart';
import 'domain/usecases/crear_primer_maestro_usecase.dart';
import 'domain/usecases/crear_usuario_usecase.dart';
import 'domain/usecases/desactivar_usuario_usecase.dart';
import 'domain/usecases/login_usecase.dart';

final passwordHasherProvider = Provider<PasswordHasher>((ref) => const PasswordHasher());

final usuarioRepositoryProvider = Provider<UsuarioRepository>((ref) {
  return UsuarioRepositoryImpl(ref.watch(appDatabaseProvider));
});

/// `count(usuario)` cacheado por Riverpod — se invalida explícitamente
/// tras crear el primer Maestro (nunca vuelve a bajar a 0 después, así
/// que no hace falta refrescarlo por ningún otro motivo).
final contarUsuariosProvider = FutureProvider<int>((ref) {
  return ref.watch(usuarioRepositoryProvider).contarUsuarios();
});

final crearPrimerMaestroUseCaseProvider = Provider<CrearPrimerMaestroUseCase>((ref) {
  return CrearPrimerMaestroUseCase(ref.watch(usuarioRepositoryProvider), ref.watch(passwordHasherProvider));
});

final loginUseCaseProvider = Provider<LoginUseCase>((ref) {
  return LoginUseCase(ref.watch(usuarioRepositoryProvider), ref.watch(passwordHasherProvider));
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

final cambiarContrasenaUsuarioUseCaseProvider = Provider<CambiarContrasenaUsuarioUseCase>((ref) {
  return CambiarContrasenaUsuarioUseCase(ref.watch(usuarioRepositoryProvider), ref.watch(passwordHasherProvider));
});

final activarUsuarioUseCaseProvider = Provider<ActivarUsuarioUseCase>((ref) {
  return ActivarUsuarioUseCase(ref.watch(usuarioRepositoryProvider));
});

final desactivarUsuarioUseCaseProvider = Provider<DesactivarUsuarioUseCase>((ref) {
  return DesactivarUsuarioUseCase(ref.watch(usuarioRepositoryProvider));
});
