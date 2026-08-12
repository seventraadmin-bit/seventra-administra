import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_info.dart';
import '../core/config/app_paths.dart';
import '../core/config/env.dart';
import '../core/database/app_database.dart';
import '../core/di/providers.dart';
import '../core/error/error_boundary.dart';
import '../core/logging/app_logger.dart';
import '../features/respaldo/domain/usecases/aplicar_restauracion_pendiente_usecase.dart';
import '../features/usuarios/data/repositories/permiso_usuario_repository_impl.dart';
import '../features/usuarios/data/repositories/usuario_repository_impl.dart';
import '../features/usuarios/domain/sesion_usuario.dart';
import '../features/usuarios/domain/usecases/restaurar_sesion_recordada_usecase.dart';
import '../features/usuarios/presentation/sesion_controller.dart';
import 'app.dart';

/// Estado inicial fijo de la sesión (Etapa 15) — cuando `bootstrap()`
/// ya validó una sesión recordada antes de `runApp`, este override
/// evita que `SesionController` empiece en `null` y tenga que
/// "alcanzar" ese estado después. Mismo mecanismo que decenas de
/// pruebas de este proyecto ya usan para fijar una sesión sin pasar por
/// `LoginUseCase` (`sesionControllerProvider.overrideWith(...)`), ahora
/// en código de producción.
class _SesionControllerPrecargada extends SesionController {
  _SesionControllerPrecargada(this._inicial);
  final SesionUsuario? _inicial;
  @override
  SesionUsuario? build() => _inicial;
}

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

    // Si hay una restauración pendiente (Etapa 14C), se aplica aquí —
    // antes de abrir la base de datos — para nunca intentar sustituir
    // un archivo que la propia conexión Drift ya tiene abierto.
    final restauracionAplicada = await AplicarRestauracionPendienteUseCase(
      databaseFile: appPaths.databaseFile,
      attachmentsDir: appPaths.attachmentsDir,
      restorePendingDir: appPaths.restorePendingDir,
      restorePendingMarkerFile: appPaths.restorePendingMarkerFile,
    ).ejecutar();
    if (restauracionAplicada) {
      logger.info('Restauración pendiente aplicada antes del arranque.');
    }

    final database = AppDatabase(openAppDatabaseConnection(appPaths.databaseFile));
    final metadata = await database.ensureMetadata(appVersion: kAppVersion);
    logger.info(
      'Metadata de instalación — id: ${metadata.installationId}, '
      'instalada: ${metadata.installedAt}, último acceso: ${metadata.lastOpenedAt}',
    );

    // "Recuérdame en este equipo" (Etapa 15) — se resuelve aquí, antes
    // de `runApp`, porque el `redirect` del router lee la sesión de
    // forma síncrona. Sin nada que recordar, o si el token ya no es
    // válido (Usuario eliminado/desactivado, o esta es una base
    // restaurada de la Etapa 14C con otros Usuarios), `sesionRecordada`
    // queda `null` y la app arranca en `/login` exactamente igual que
    // hoy.
    final sesionRecordada = await RestaurarSesionRecordadaUseCase(
      UsuarioRepositoryImpl(database),
      PermisoUsuarioRepositoryImpl(database),
    ).ejecutar();
    if (sesionRecordada != null) {
      logger.info('Sesión recordada restaurada — usuario: ${sesionRecordada.nombreUsuario}');
    }

    runApp(
      ProviderScope(
        overrides: [
          envProvider.overrideWithValue(env),
          appLoggerProvider.overrideWithValue(logger),
          appPathsProvider.overrideWithValue(appPaths),
          appDatabaseProvider.overrideWithValue(database),
          if (sesionRecordada != null)
            sesionControllerProvider.overrideWith(() => _SesionControllerPrecargada(sesionRecordada)),
        ],
        child: RisegOneApp(),
      ),
    );
  });
}
