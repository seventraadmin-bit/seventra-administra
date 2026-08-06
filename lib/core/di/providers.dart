import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_paths.dart';
import '../config/env.dart';
import '../database/app_database.dart';
import '../logging/app_logger.dart';
import '../permissions/permission_service.dart';
import '../utils/clock.dart';

/// Providers raíz de RISEG ONE.
///
/// Los valores que dependen de inicialización asíncrona (rutas de archivo,
/// conexión a la base de datos) se resuelven una sola vez en
/// `bootstrap.dart` antes de `runApp`, y se inyectan aquí mediante
/// `ProviderScope(overrides: [...])`. Los providers declarados abajo nunca
/// deberían leerse sin haber sido sobreescritos primero.

final envProvider = Provider<Env>((ref) {
  throw UnimplementedError('envProvider debe sobreescribirse en bootstrap.');
});

final appLoggerProvider = Provider<AppLogger>((ref) {
  throw UnimplementedError('appLoggerProvider debe sobreescribirse en bootstrap.');
});

final appPathsProvider = Provider<AppPaths>((ref) {
  throw UnimplementedError('appPathsProvider debe sobreescribirse en bootstrap.');
});

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('appDatabaseProvider debe sobreescribirse en bootstrap.');
});

final permissionServiceProvider = Provider<PermissionService>((ref) {
  final env = ref.watch(envProvider);
  return resolvePermissionService(env);
});

final clockProvider = Provider<Clock>((ref) => const SystemClock());
