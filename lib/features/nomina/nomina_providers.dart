import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../finanzas/finanzas_providers.dart';
import '../organizacion/organizacion_providers.dart';
import '../personal/personal_providers.dart';
import 'data/repositories/nomina_repository_impl.dart';
import 'data/repositories/pago_nomina_repository_impl.dart';
import 'domain/repositories/nomina_repository.dart';
import 'domain/repositories/pago_nomina_repository.dart';
import 'domain/usecases/actualizar_distribucion_nomina_usecase.dart';
import 'domain/usecases/actualizar_movimientos_nomina_usecase.dart';
import 'domain/usecases/actualizar_nomina_desde_personal_usecase.dart';
import 'domain/usecases/adjuntar_comprobante_pago_nomina_usecase.dart';
import 'domain/usecases/cancelar_pago_nomina_usecase.dart';
import 'domain/usecases/cerrar_nomina_usecase.dart';
import 'domain/usecases/corregir_pago_nomina_usecase.dart';
import 'domain/usecases/evaluar_renglones_requieren_revision_usecase.dart';
import 'domain/usecases/generar_nomina_usecase.dart';
import 'domain/usecases/registrar_pago_nomina_usecase.dart';
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

// --- Etapa 6D — Pagos e integración con Finanzas ---

final pagoNominaRepositoryProvider = Provider<PagoNominaRepository>((ref) {
  return PagoNominaRepositoryImpl(ref.watch(appDatabaseProvider), ref.watch(egresoRepositoryProvider));
});

final registrarPagoNominaUseCaseProvider = Provider<RegistrarPagoNominaUseCase>((ref) {
  return RegistrarPagoNominaUseCase(
    ref.watch(pagoNominaRepositoryProvider),
    ref.watch(nominaRepositoryProvider),
    ref.watch(generarCodigoUseCaseProvider),
  );
});

final cancelarPagoNominaUseCaseProvider = Provider<CancelarPagoNominaUseCase>((ref) {
  return CancelarPagoNominaUseCase(ref.watch(pagoNominaRepositoryProvider));
});

final corregirPagoNominaUseCaseProvider = Provider<CorregirPagoNominaUseCase>((ref) {
  return CorregirPagoNominaUseCase(ref.watch(pagoNominaRepositoryProvider));
});

final adjuntarComprobantePagoNominaUseCaseProvider = Provider<AdjuntarComprobantePagoNominaUseCase>((ref) {
  return AdjuntarComprobantePagoNominaUseCase(ref.watch(pagoNominaRepositoryProvider), ref.watch(attachmentStorageProvider));
});
