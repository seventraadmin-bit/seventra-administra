import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../organizacion/organizacion_providers.dart';
import '../personal/personal_providers.dart';
import 'data/repositories/nomina_repository_impl.dart';
import 'domain/repositories/nomina_repository.dart';
import 'domain/usecases/actualizar_distribucion_nomina_usecase.dart';
import 'domain/usecases/actualizar_movimientos_nomina_usecase.dart';
import 'domain/usecases/actualizar_nomina_desde_personal_usecase.dart';
import 'domain/usecases/cerrar_nomina_usecase.dart';
import 'domain/usecases/evaluar_renglones_requieren_revision_usecase.dart';
import 'domain/usecases/generar_nomina_usecase.dart';
import 'domain/usecases/resolver_sueldo_empleado_nomina.dart';

/// Providers del dominio Nómina (Etapa 6C) — nace aquí, separado de
/// `personal` (mismo criterio que `finanzas` en la Etapa 4J.1).
final nominaRepositoryProvider = Provider<NominaRepository>((ref) {
  return NominaRepositoryImpl(ref.watch(appDatabaseProvider));
});

final resolverSueldoEmpleadoNominaProvider = Provider<ResolverSueldoEmpleadoNomina>((ref) {
  return ResolverSueldoEmpleadoNomina(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(asignacionServicioRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
    ref.watch(catalogoRepositoryProvider),
  );
});

final generarNominaUseCaseProvider = Provider<GenerarNominaUseCase>((ref) {
  return GenerarNominaUseCase(
    ref.watch(nominaRepositoryProvider),
    ref.watch(empleadoRepositoryProvider),
    ref.watch(puestoRepositoryProvider),
    ref.watch(catalogoRepositoryProvider),
    ref.watch(resolverSueldoEmpleadoNominaProvider),
    ref.watch(generarCodigoUseCaseProvider),
  );
});

final actualizarNominaDesdePersonalUseCaseProvider = Provider<ActualizarNominaDesdePersonalUseCase>((ref) {
  return ActualizarNominaDesdePersonalUseCase(
    ref.watch(nominaRepositoryProvider),
    ref.watch(empleadoRepositoryProvider),
    ref.watch(puestoRepositoryProvider),
    ref.watch(catalogoRepositoryProvider),
    ref.watch(resolverSueldoEmpleadoNominaProvider),
  );
});

final actualizarMovimientosNominaUseCaseProvider = Provider<ActualizarMovimientosNominaUseCase>((ref) {
  return ActualizarMovimientosNominaUseCase(ref.watch(nominaRepositoryProvider));
});

final actualizarDistribucionNominaUseCaseProvider = Provider<ActualizarDistribucionNominaUseCase>((ref) {
  return ActualizarDistribucionNominaUseCase(ref.watch(nominaRepositoryProvider));
});

final evaluarRenglonesRequierenRevisionUseCaseProvider = Provider<EvaluarRenglonesRequierenRevisionUseCase>((ref) {
  return EvaluarRenglonesRequierenRevisionUseCase(
    ref.watch(nominaRepositoryProvider),
    ref.watch(empleadoRepositoryProvider),
    ref.watch(resolverSueldoEmpleadoNominaProvider),
  );
});

final cerrarNominaUseCaseProvider = Provider<CerrarNominaUseCase>((ref) {
  return CerrarNominaUseCase(ref.watch(nominaRepositoryProvider), ref.watch(evaluarRenglonesRequierenRevisionUseCaseProvider));
});
