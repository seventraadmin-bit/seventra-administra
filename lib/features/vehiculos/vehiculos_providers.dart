import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../organizacion/organizacion_providers.dart';
import '../personal/personal_providers.dart';
import 'data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'data/repositories/vehiculo_kilometraje_repository_impl.dart';
import 'data/repositories/vehiculo_repository_impl.dart';
import 'domain/repositories/asignacion_vehiculo_repository.dart';
import 'domain/repositories/vehiculo_kilometraje_repository.dart';
import 'domain/repositories/vehiculo_repository.dart';
import 'domain/usecases/actualizar_fotografia_vehiculo_usecase.dart';
import 'domain/usecases/asignar_vehiculo_usecase.dart';
import 'domain/usecases/cambiar_asignacion_vehiculo_usecase.dart';
import 'domain/usecases/cambiar_estatus_vehiculo_usecase.dart';
import 'domain/usecases/corregir_vehiculo_usecase.dart';
import 'domain/usecases/crear_vehiculo_usecase.dart';
import 'domain/usecases/dar_de_baja_vehiculo_usecase.dart';
import 'domain/usecases/obtener_opciones_asignacion_vehiculo_usecase.dart';
import 'domain/usecases/registrar_kilometraje_vehiculo_usecase.dart';
import 'domain/usecases/retirar_asignacion_vehiculo_usecase.dart';

/// Providers del dominio Vehículos (Etapa 8A) — nace aquí, separado de
/// Inventario y del resto de dominios, mismo criterio que cada dominio
/// nuevo desde 4J.1.
///
/// `asignacionVehiculoRepositoryProvider` se declara antes que
/// `vehiculoRepositoryProvider` porque este último lo necesita como
/// dependencia (repositorio compone repositorio, Etapa 8B — ver el doc
/// comment de `VehiculoRepositoryImpl`).
final asignacionVehiculoRepositoryProvider = Provider<AsignacionVehiculoRepository>((ref) {
  return AsignacionVehiculoRepositoryImpl(ref.watch(appDatabaseProvider));
});

final vehiculoRepositoryProvider = Provider<VehiculoRepository>((ref) {
  return VehiculoRepositoryImpl(ref.watch(appDatabaseProvider), ref.watch(asignacionVehiculoRepositoryProvider));
});

final crearVehiculoUseCaseProvider = Provider<CrearVehiculoUseCase>((ref) {
  return CrearVehiculoUseCase(ref.watch(vehiculoRepositoryProvider), ref.watch(generarCodigoUseCaseProvider));
});

final corregirVehiculoUseCaseProvider = Provider<CorregirVehiculoUseCase>((ref) {
  return CorregirVehiculoUseCase(ref.watch(vehiculoRepositoryProvider));
});

final cambiarEstatusVehiculoUseCaseProvider = Provider<CambiarEstatusVehiculoUseCase>((ref) {
  return CambiarEstatusVehiculoUseCase(ref.watch(vehiculoRepositoryProvider));
});

final darDeBajaVehiculoUseCaseProvider = Provider<DarDeBajaVehiculoUseCase>((ref) {
  return DarDeBajaVehiculoUseCase(ref.watch(vehiculoRepositoryProvider));
});

final actualizarFotografiaVehiculoUseCaseProvider = Provider<ActualizarFotografiaVehiculoUseCase>((ref) {
  return ActualizarFotografiaVehiculoUseCase(
    ref.watch(vehiculoRepositoryProvider),
    ref.watch(attachmentRepositoryProvider),
    ref.watch(attachmentStorageProvider),
  );
});

/// Providers de Asignaciones y kilometraje (Etapa 8B).
final vehiculoKilometrajeRepositoryProvider = Provider<VehiculoKilometrajeRepository>((ref) {
  return VehiculoKilometrajeRepositoryImpl(ref.watch(appDatabaseProvider));
});

final asignarVehiculoUseCaseProvider = Provider<AsignarVehiculoUseCase>((ref) {
  return AsignarVehiculoUseCase(
    ref.watch(vehiculoRepositoryProvider),
    ref.watch(asignacionVehiculoRepositoryProvider),
    ref.watch(vehiculoKilometrajeRepositoryProvider),
  );
});

final cambiarAsignacionVehiculoUseCaseProvider = Provider<CambiarAsignacionVehiculoUseCase>((ref) {
  return CambiarAsignacionVehiculoUseCase(ref.watch(asignacionVehiculoRepositoryProvider));
});

final retirarAsignacionVehiculoUseCaseProvider = Provider<RetirarAsignacionVehiculoUseCase>((ref) {
  return RetirarAsignacionVehiculoUseCase(
    ref.watch(asignacionVehiculoRepositoryProvider),
    ref.watch(vehiculoKilometrajeRepositoryProvider),
  );
});

final registrarKilometrajeVehiculoUseCaseProvider = Provider<RegistrarKilometrajeVehiculoUseCase>((ref) {
  return RegistrarKilometrajeVehiculoUseCase(
    ref.watch(vehiculoKilometrajeRepositoryProvider),
    ref.watch(vehiculoRepositoryProvider),
  );
});

/// Dependencia cruzada a `personal`/`organizacion` (lectura) — mismo
/// patrón ya establecido por
/// `obtenerEmpleadosResponsablesServicioUseCaseProvider` (Inventario).
/// La UI de Vehículos nunca importa `personal_providers.dart`/
/// `organizacion_providers.dart` directamente: solo conoce este caso
/// de uso.
final obtenerOpcionesAsignacionVehiculoUseCaseProvider = Provider<ObtenerOpcionesAsignacionVehiculoUseCase>((ref) {
  return ObtenerOpcionesAsignacionVehiculoUseCase(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
  );
});
