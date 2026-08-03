import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_info.dart';
import '../core/config/app_paths.dart';
import '../core/config/env.dart';
import '../core/database/app_database.dart';
import '../core/di/providers.dart';
import '../core/error/error_boundary.dart';
import '../core/logging/app_logger.dart';
import 'app.dart';

/// Orquesta el arranque completo de RISEG ONE, en orden:
/// logging → manejo de errores → rutas de datos → base de datos → `runApp`.
///
/// Todo ocurre dentro de una misma zona protegida ([runGuardedApp]) para que
/// ningún error de inicialización, incluidos los asíncronos, se pierda.
void bootstrap() {
  final env = Env.resolve();
  final logger = AppLogger.console();

  runGuardedApp(logger, () async {
    WidgetsFlutterBinding.ensureInitialized();
    installErrorBoundary(logger);

    logger.info('Iniciando RISEG ONE — entorno: ${env.name}');

    final appPaths = await AppPaths.resolve(env);
    logger.info('Carpeta de datos: ${appPaths.rootDir}');

    final database = AppDatabase(openAppDatabaseConnection(appPaths.databaseFile));
    final metadata = await database.ensureMetadata(appVersion: kAppVersion);
    logger.info(
      'Metadata de instalación — id: ${metadata.installationId}, '
      'instalada: ${metadata.installedAt}, último acceso: ${metadata.lastOpenedAt}',
    );

    runApp(
      ProviderScope(
        overrides: [
          envProvider.overrideWithValue(env),
          appLoggerProvider.overrideWithValue(logger),
          appPathsProvider.overrideWithValue(appPaths),
          appDatabaseProvider.overrideWithValue(database),
        ],
        child: const RisegOneApp(),
      ),
    );
  });
}
