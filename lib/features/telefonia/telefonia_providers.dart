import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/features/inventario/inventario_providers.dart';

import '../../core/di/providers.dart';
import '../organizacion/organizacion_providers.dart';
import '../personal/personal_providers.dart';
import 'data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'data/repositories/linea_telefonica_equipo_repository_impl.dart';
import 'data/repositories/linea_telefonica_repository_impl.dart';
import 'data/repositories/recarga_linea_telefonica_repository_impl.dart';
import 'domain/repositories/asignacion_linea_telefonica_repository.dart';
import 'domain/repositories/linea_telefonica_equipo_repository.dart';
import 'domain/repositories/linea_telefonica_repository.dart';
import 'domain/repositories/recarga_linea_telefonica_repository.dart';
import 'domain/usecases/adjuntar_comprobante_recarga_linea_telefonica_usecase.dart';
import 'domain/usecases/asignar_linea_telefonica_usecase.dart';
import 'domain/usecases/asociar_equipo_linea_telefonica_usecase.dart';
import 'domain/usecases/cambiar_asignacion_linea_telefonica_usecase.dart';
import 'domain/usecases/cambiar_equipo_linea_telefonica_usecase.dart';
import 'domain/usecases/cambiar_estatus_linea_telefonica_usecase.dart';
import 'domain/usecases/corregir_linea_telefonica_usecase.dart';
import 'domain/usecases/crear_linea_telefonica_usecase.dart';
import 'domain/usecases/dar_de_baja_linea_telefonica_usecase.dart';
import 'domain/usecases/obtener_equipos_disponibles_linea_telefonica_usecase.dart';
import 'domain/usecases/obtener_opciones_asignacion_linea_telefonica_usecase.dart';
import 'domain/usecases/registrar_recarga_linea_telefonica_usecase.dart';
import 'domain/usecases/retirar_asignacion_linea_telefonica_usecase.dart';
import 'domain/usecases/retirar_equipo_linea_telefonica_usecase.dart';

/// Providers del dominio Telefonía (Etapa 9A) — nace aquí, separado de
/// Inventario/Vehículos y del resto de dominios, mismo criterio que
/// cada dominio nuevo desde 4J.1.
///
/// `asignacionLineaTelefonicaRepositoryProvider` se declara antes que
/// `lineaTelefonicaRepositoryProvider`/`lineaTelefonicaEquipoRepositoryProvider`
/// porque ambos lo necesitan como dependencia (repositorio compone
/// repositorio, Etapa 9B).
final asignacionLineaTelefonicaRepositoryProvider = Provider<AsignacionLineaTelefonicaRepository>((ref) {
  return AsignacionLineaTelefonicaRepositoryImpl(ref.watch(appDatabaseProvider));
});

/// Compone con el `AsignacionRepository`/`InventarioRepository` reales
/// de Inventario (Etapa 9B) — ver el doc comment de
/// `LineaTelefonicaEquipoRepository` para la decisión completa de
/// consistencia con Inventario.
final lineaTelefonicaEquipoRepositoryProvider = Provider<LineaTelefonicaEquipoRepository>((ref) {
  return LineaTelefonicaEquipoRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(asignacionLineaTelefonicaRepositoryProvider),
    ref.watch(asignacionRepositoryProvider),
    ref.watch(inventarioRepositoryProvider),
  );
});

final lineaTelefonicaRepositoryProvider = Provider<LineaTelefonicaRepository>((ref) {
  return LineaTelefonicaRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(asignacionLineaTelefonicaRepositoryProvider),
    ref.watch(lineaTelefonicaEquipoRepositoryProvider),
  );
});

final crearLineaTelefonicaUseCaseProvider = Provider<CrearLineaTelefonicaUseCase>((ref) {
  return CrearLineaTelefonicaUseCase(ref.watch(lineaTelefonicaRepositoryProvider), ref.watch(generarCodigoUseCaseProvider));
});

final corregirLineaTelefonicaUseCaseProvider = Provider<CorregirLineaTelefonicaUseCase>((ref) {
  return CorregirLineaTelefonicaUseCase(ref.watch(lineaTelefonicaRepositoryProvider));
});

final cambiarEstatusLineaTelefonicaUseCaseProvider = Provider<CambiarEstatusLineaTelefonicaUseCase>((ref) {
  return CambiarEstatusLineaTelefonicaUseCase(ref.watch(lineaTelefonicaRepositoryProvider));
});

final darDeBajaLineaTelefonicaUseCaseProvider = Provider<DarDeBajaLineaTelefonicaUseCase>((ref) {
  return DarDeBajaLineaTelefonicaUseCase(ref.watch(lineaTelefonicaRepositoryProvider));
});

/// Recargas (Etapa 9C) — operación prepago, sin planes/contratos.
final recargaLineaTelefonicaRepositoryProvider = Provider<RecargaLineaTelefonicaRepository>((ref) {
  return RecargaLineaTelefonicaRepositoryImpl(ref.watch(appDatabaseProvider));
});

final registrarRecargaLineaTelefonicaUseCaseProvider = Provider<RegistrarRecargaLineaTelefonicaUseCase>((ref) {
  return RegistrarRecargaLineaTelefonicaUseCase(
    ref.watch(recargaLineaTelefonicaRepositoryProvider),
    ref.watch(lineaTelefonicaRepositoryProvider),
  );
});

final adjuntarComprobanteRecargaLineaTelefonicaUseCaseProvider =
    Provider<AdjuntarComprobanteRecargaLineaTelefonicaUseCase>((ref) {
  return AdjuntarComprobanteRecargaLineaTelefonicaUseCase(
    ref.watch(recargaLineaTelefonicaRepositoryProvider),
    ref.watch(attachmentStorageProvider),
  );
});

/// Providers de Asignaciones y equipo asociado (Etapa 9B).
final asignarLineaTelefonicaUseCaseProvider = Provider<AsignarLineaTelefonicaUseCase>((ref) {
  return AsignarLineaTelefonicaUseCase(
    ref.watch(lineaTelefonicaRepositoryProvider),
    ref.watch(asignacionLineaTelefonicaRepositoryProvider),
    ref.watch(lineaTelefonicaEquipoRepositoryProvider),
  );
});

final cambiarAsignacionLineaTelefonicaUseCaseProvider = Provider<CambiarAsignacionLineaTelefonicaUseCase>((ref) {
  return CambiarAsignacionLineaTelefonicaUseCase(
    ref.watch(asignacionLineaTelefonicaRepositoryProvider),
    ref.watch(lineaTelefonicaEquipoRepositoryProvider),
  );
});

final retirarAsignacionLineaTelefonicaUseCaseProvider = Provider<RetirarAsignacionLineaTelefonicaUseCase>((ref) {
  return RetirarAsignacionLineaTelefonicaUseCase(
    ref.watch(asignacionLineaTelefonicaRepositoryProvider),
    ref.watch(lineaTelefonicaEquipoRepositoryProvider),
  );
});

final asociarEquipoLineaTelefonicaUseCaseProvider = Provider<AsociarEquipoLineaTelefonicaUseCase>((ref) {
  return AsociarEquipoLineaTelefonicaUseCase(
    ref.watch(lineaTelefonicaRepositoryProvider),
    ref.watch(lineaTelefonicaEquipoRepositoryProvider),
    ref.watch(inventarioRepositoryProvider),
  );
});

final cambiarEquipoLineaTelefonicaUseCaseProvider = Provider<CambiarEquipoLineaTelefonicaUseCase>((ref) {
  return CambiarEquipoLineaTelefonicaUseCase(
    ref.watch(lineaTelefonicaRepositoryProvider),
    ref.watch(lineaTelefonicaEquipoRepositoryProvider),
    ref.watch(inventarioRepositoryProvider),
  );
});

final retirarEquipoLineaTelefonicaUseCaseProvider = Provider<RetirarEquipoLineaTelefonicaUseCase>((ref) {
  return RetirarEquipoLineaTelefonicaUseCase(ref.watch(lineaTelefonicaEquipoRepositoryProvider));
});

/// Dependencia cruzada a `personal`/`organizacion`/`inventario`
/// (lectura) — mismo patrón ya establecido por
/// `ObtenerOpcionesAsignacionVehiculoUseCase`. La UI de Telefonía nunca
/// importa los repositorios de esos dominios directamente.
final obtenerOpcionesAsignacionLineaTelefonicaUseCaseProvider =
    Provider<ObtenerOpcionesAsignacionLineaTelefonicaUseCase>((ref) {
  return ObtenerOpcionesAsignacionLineaTelefonicaUseCase(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
  );
});

final obtenerEquiposDisponiblesLineaTelefonicaUseCaseProvider =
    Provider<ObtenerEquiposDisponiblesLineaTelefonicaUseCase>((ref) {
  return ObtenerEquiposDisponiblesLineaTelefonicaUseCase(ref.watch(inventarioRepositoryProvider));
});
