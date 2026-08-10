import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../organizacion/organizacion_providers.dart';
import 'data/repositories/vehiculo_repository_impl.dart';
import 'domain/repositories/vehiculo_repository.dart';
import 'domain/usecases/actualizar_fotografia_vehiculo_usecase.dart';
import 'domain/usecases/cambiar_estatus_vehiculo_usecase.dart';
import 'domain/usecases/corregir_vehiculo_usecase.dart';
import 'domain/usecases/crear_vehiculo_usecase.dart';
import 'domain/usecases/dar_de_baja_vehiculo_usecase.dart';

/// Providers del dominio Vehículos (Etapa 8A) — nace aquí, separado de
/// Inventario y del resto de dominios, mismo criterio que cada dominio
/// nuevo desde 4J.1.
final vehiculoRepositoryProvider = Provider<VehiculoRepository>((ref) {
  return VehiculoRepositoryImpl(ref.watch(appDatabaseProvider));
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
