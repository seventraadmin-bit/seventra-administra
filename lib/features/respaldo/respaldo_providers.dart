import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/permissions/authorization_service.dart';
import '../usuarios/usuarios_providers.dart';
import 'domain/abridor_ubicacion.dart';
import 'domain/usecases/crear_respaldo_usecase.dart';
import 'domain/usecases/eliminar_respaldo_usecase.dart';
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
      () => ref
          .read(prepararRestauracionUseCaseProvider)
          .ejecutar(rutaZip: rutaZip, appSchemaVersionActual: ref.read(appSchemaVersionProvider)),
      RestauracionErrorInesperado.new,
    );
  };
});

typedef VerificarRespaldoAutorizado = Future<ResultadoValidarPaqueteRespaldo> Function({required String rutaZip});

/// Verificar un respaldo abre y recorre su contenido: la misma clase de
/// acceso a datos que restaurarlo, así que exige el mismo Maestro.
final verificarRespaldoAutorizadoProvider = Provider<VerificarRespaldoAutorizado>((ref) {
  return ({required String rutaZip}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref
          .read(validarPaqueteRespaldoUseCaseProvider)
          .ejecutar(rutaZip: rutaZip, appSchemaVersionActual: ref.read(appSchemaVersionProvider)),
      PaqueteRespaldoErrorInesperado.new,
    );
  };
});

final eliminarRespaldoUseCaseProvider = Provider<EliminarRespaldoUseCase>((ref) {
  return EliminarRespaldoUseCase(restorePendingMarkerFile: ref.watch(appPathsProvider).restorePendingMarkerFile);
});

typedef EliminarRespaldoAutorizado =
    Future<ResultadoEliminarRespaldo> Function({required String rutaZip, required bool esPreventivo});

/// Borrar un respaldo es destructivo sobre la única copia de seguridad
/// que puede existir: misma facultad extraordinaria que crear y
/// restaurar.
final eliminarRespaldoAutorizadoProvider = Provider<EliminarRespaldoAutorizado>((ref) {
  return ({required String rutaZip, required bool esPreventivo}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(eliminarRespaldoUseCaseProvider).ejecutar(rutaZip: rutaZip, esPreventivo: esPreventivo),
      EliminarRespaldoErrorInesperado.new,
    );
  };
});

/// Abrir el Explorador en la carpeta de un respaldo. No lee ni escribe
/// datos de la aplicación, así que no lleva `exigirMaestro`: la pantalla
/// entera ya es Maestro-only.
final abridorUbicacionProvider = Provider<AbridorUbicacion>((ref) => const AbridorUbicacion());

/// Directorio de respaldos, expuesto para que la pantalla liste los
/// `.zip` ya creados (`AppPaths.backupsDir`) sin necesitar un provider
/// propio — es el mismo `AppPaths` que ya usa el resto de la app.
final backupsDirProvider = Provider<String>((ref) => ref.watch(appPathsProvider).backupsDir);
