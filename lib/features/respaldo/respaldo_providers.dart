import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/permissions/authorization_service.dart';
import '../usuarios/usuarios_providers.dart';
import 'domain/usecases/crear_respaldo_usecase.dart';
import 'domain/usecases/preparar_restauracion_usecase.dart';
import 'domain/usecases/validar_paquete_respaldo_usecase.dart';

final crearRespaldoUseCaseProvider = Provider<CrearRespaldoUseCase>((ref) {
  final appPaths = ref.watch(appPathsProvider);
  return CrearRespaldoUseCase(databaseFile: appPaths.databaseFile, attachmentsDir: appPaths.attachmentsDir);
});

final validarPaqueteRespaldoUseCaseProvider = Provider<ValidarPaqueteRespaldoUseCase>((ref) {
  return ValidarPaqueteRespaldoUseCase();
});

final prepararRestauracionUseCaseProvider = Provider<PrepararRestauracionUseCase>((ref) {
  final appPaths = ref.watch(appPathsProvider);
  return PrepararRestauracionUseCase(
    backupsDir: appPaths.backupsDir,
    restorePendingDir: appPaths.restorePendingDir,
    restorePendingMarkerFile: appPaths.restorePendingMarkerFile,
    validar: ref.watch(validarPaqueteRespaldoUseCaseProvider),
    crearRespaldo: ref.watch(crearRespaldoUseCaseProvider),
  );
});

/// `schemaVersion` de esta build de RISEG ONE — usado para rechazar un
/// paquete de respaldo creado con una versión más nueva de la
/// aplicación (ver `ValidarPaqueteRespaldoUseCase`).
final appSchemaVersionProvider = Provider<int>((ref) {
  return ref.watch(appDatabaseProvider).schemaVersion;
});

typedef CrearRespaldoAutorizado = Future<ResultadoCrearRespaldo> Function({required String destinoZip});

/// Facultad exclusiva del Usuario Maestro (mismo mecanismo que la
/// eliminación física de la Etapa 11D, `exigirMaestro`) — crear o
/// restaurar un respaldo reemplaza datos de toda la aplicación, así que
/// ningún permiso dinámico de `PermisoUsuario` puede otorgarla.
final crearRespaldoAutorizadoProvider = Provider<CrearRespaldoAutorizado>((ref) {
  return ({required String destinoZip}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(crearRespaldoUseCaseProvider).ejecutar(destinoZip: destinoZip),
      RespaldoErrorInesperado.new,
    );
  };
});

typedef RestaurarAutorizado = Future<ResultadoPrepararRestauracion> Function({required String rutaZip});

final restaurarAutorizadoProvider = Provider<RestaurarAutorizado>((ref) {
  return ({required String rutaZip}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(prepararRestauracionUseCaseProvider).ejecutar(
            rutaZip: rutaZip,
            appSchemaVersionActual: ref.read(appSchemaVersionProvider),
          ),
      RestauracionErrorInesperado.new,
    );
  };
});

/// Directorio de respaldos, expuesto para que la pantalla liste los
/// `.zip` ya creados (`AppPaths.backupsDir`) sin necesitar un provider
/// propio — es el mismo `AppPaths` que ya usa el resto de la app.
final backupsDirProvider = Provider<String>((ref) => ref.watch(appPathsProvider).backupsDir);
