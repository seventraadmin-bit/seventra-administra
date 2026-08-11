import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../organizacion/organizacion_providers.dart';
import 'data/repositories/linea_telefonica_plan_repository_impl.dart';
import 'data/repositories/linea_telefonica_repository_impl.dart';
import 'domain/repositories/linea_telefonica_plan_repository.dart';
import 'domain/repositories/linea_telefonica_repository.dart';
import 'domain/usecases/cambiar_estatus_linea_telefonica_usecase.dart';
import 'domain/usecases/corregir_linea_telefonica_usecase.dart';
import 'domain/usecases/crear_linea_telefonica_usecase.dart';
import 'domain/usecases/dar_de_baja_linea_telefonica_usecase.dart';
import 'domain/usecases/registrar_plan_linea_telefonica_usecase.dart';

/// Providers del dominio Telefonía (Etapa 9A) — nace aquí, separado de
/// Inventario/Vehículos y del resto de dominios, mismo criterio que
/// cada dominio nuevo desde 4J.1.
final lineaTelefonicaRepositoryProvider = Provider<LineaTelefonicaRepository>((ref) {
  return LineaTelefonicaRepositoryImpl(ref.watch(appDatabaseProvider));
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

final lineaTelefonicaPlanRepositoryProvider = Provider<LineaTelefonicaPlanRepository>((ref) {
  return LineaTelefonicaPlanRepositoryImpl(ref.watch(appDatabaseProvider));
});

final registrarPlanLineaTelefonicaUseCaseProvider = Provider<RegistrarPlanLineaTelefonicaUseCase>((ref) {
  return RegistrarPlanLineaTelefonicaUseCase(
    ref.watch(lineaTelefonicaPlanRepositoryProvider),
    ref.watch(lineaTelefonicaRepositoryProvider),
  );
});
