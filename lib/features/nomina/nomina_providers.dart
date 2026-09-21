import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/permissions/authorization_service.dart';
import '../descuentos_personal/descuentos_personal_providers.dart';
import '../finanzas/finanzas_providers.dart';
import '../inventario/inventario_providers.dart';
import '../organizacion/organizacion_providers.dart';
import '../personal/personal_providers.dart';
import '../tiempos_extra/tiempos_extra_providers.dart';
import '../usuarios/presentation/sesion_controller.dart';
import '../usuarios/usuarios_providers.dart';
import 'data/repositories/nomina_repository_impl.dart';
import 'data/repositories/pago_nomina_repository_impl.dart';
import 'domain/repositories/nomina_repository.dart';
import 'domain/repositories/pago_nomina_repository.dart';
import 'domain/usecases/actualizar_nomina_desde_personal_usecase.dart';
import 'domain/usecases/actualizar_renglon_nomina_usecase.dart';
import 'domain/usecases/adjuntar_comprobante_pago_nomina_usecase.dart';
import 'domain/usecases/cancelar_nomina_usecase.dart';
import 'domain/usecases/cancelar_pago_nomina_usecase.dart';
import 'domain/usecases/cerrar_nomina_usecase.dart';
import 'domain/usecases/corregir_pago_nomina_usecase.dart';
import 'domain/usecases/corregir_renglon_nomina_usecase.dart';
import 'domain/usecases/eliminar_cadena_prueba_nomina_usecase.dart';
import 'data/pdf/nomina_dispersion_pdf_renderer.dart';
import 'domain/usecases/eliminar_nomina_fisicamente_usecase.dart';
import 'domain/usecases/evaluar_renglones_requieren_revision_usecase.dart';
import 'domain/usecases/generar_nomina_dispersion_pdf_usecase.dart';
import 'domain/usecases/generar_nomina_usecase.dart';
import 'domain/usecases/reconciliar_estatus_pago_nomina_usecase.dart';
import 'domain/usecases/registrar_pago_nomina_usecase.dart';
import 'domain/usecases/resolver_sueldo_empleado_nomina.dart';

/// Providers del dominio Nómina (Etapa 6C) — nace aquí, separado de
/// `personal` (mismo criterio que `finanzas` en la Etapa 4J.1).
final nominaRepositoryProvider = Provider<NominaRepository>((ref) {
  return NominaRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(asignacionRepositoryProvider),
    ref.watch(descuentoProgramadoRepositoryProvider),
    ref.watch(tiempoExtraRepositoryProvider),
    ref.watch(pagoNominaRepositoryProvider),
  );
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

final actualizarRenglonNominaUseCaseProvider = Provider<ActualizarRenglonNominaUseCase>((ref) {
  return ActualizarRenglonNominaUseCase(ref.watch(nominaRepositoryProvider));
});

final corregirRenglonNominaUseCaseProvider = Provider<CorregirRenglonNominaUseCase>((ref) {
  return CorregirRenglonNominaUseCase(ref.watch(nominaRepositoryProvider), ref.watch(pagoNominaRepositoryProvider));
});

final cancelarNominaUseCaseProvider = Provider<CancelarNominaUseCase>((ref) {
  return CancelarNominaUseCase(ref.watch(nominaRepositoryProvider), ref.watch(pagoNominaRepositoryProvider));
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

// Eliminación física extraordinaria (Etapa 15) — facultad exclusiva del
// Usuario Maestro, mismo patrón exacto que Compra/Cliente/Servicio
// (`exigirMaestro`, nunca `AuthorizationService.verificar`).
final eliminarNominaFisicamenteUseCaseProvider = Provider<EliminarNominaFisicamenteUseCase>((ref) {
  return EliminarNominaFisicamenteUseCase(ref.watch(nominaRepositoryProvider));
});

typedef EliminarNominaFisicamenteAutorizado = Future<EliminarNominaFisicamenteResultado> Function({
  required String nominaId,
  required MotivoEliminacionFisicaNomina motivo,
  String? detalle,
});

final eliminarNominaFisicamenteAutorizadoProvider = Provider<EliminarNominaFisicamenteAutorizado>((ref) {
  return ({required String nominaId, required MotivoEliminacionFisicaNomina motivo, String? detalle}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(eliminarNominaFisicamenteUseCaseProvider).ejecutar(
            nominaId: nominaId,
            motivo: motivo,
            detalle: detalle,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      EliminarNominaFisicamenteErrorInesperado.new,
    );
  };
});

// "Eliminar cadena de prueba" (Etapa 15, ampliación de la limpieza
// segura de datos de prueba) — ofrecida SOLO cuando la eliminación
// física normal está bloqueada (Nómina Cerrada/Pagada, o con
// PagoNomina); misma facultad exclusiva Maestro.
final eliminarCadenaPruebaNominaUseCaseProvider = Provider<EliminarCadenaPruebaNominaUseCase>((ref) {
  return EliminarCadenaPruebaNominaUseCase(ref.watch(nominaRepositoryProvider));
});

typedef EliminarCadenaPruebaNominaAutorizado = Future<EliminarCadenaPruebaNominaResultado> Function({
  required String nominaId,
  required MotivoCadenaPruebaNomina motivo,
  String? detalle,
});

final eliminarCadenaPruebaNominaAutorizadoProvider = Provider<EliminarCadenaPruebaNominaAutorizado>((ref) {
  return ({required String nominaId, required MotivoCadenaPruebaNomina motivo, String? detalle}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(eliminarCadenaPruebaNominaUseCaseProvider).ejecutar(
            nominaId: nominaId,
            motivo: motivo,
            detalle: detalle,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      EliminarCadenaPruebaNominaErrorInesperado.new,
    );
  };
});

// --- Etapa 6D — Pagos e integración con Finanzas ---

final pagoNominaRepositoryProvider = Provider<PagoNominaRepository>((ref) {
  return PagoNominaRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(egresoRepositoryProvider),
    ref.watch(descuentoProgramadoRepositoryProvider),
  );
});

final reconciliarEstatusPagoNominaUseCaseProvider = Provider<ReconciliarEstatusPagoNominaUseCase>((ref) {
  return ReconciliarEstatusPagoNominaUseCase(ref.watch(nominaRepositoryProvider), ref.watch(pagoNominaRepositoryProvider));
});

final registrarPagoNominaUseCaseProvider = Provider<RegistrarPagoNominaUseCase>((ref) {
  return RegistrarPagoNominaUseCase(
    ref.watch(pagoNominaRepositoryProvider),
    ref.watch(nominaRepositoryProvider),
    ref.watch(generarCodigoUseCaseProvider),
    ref.watch(cuentaFinancieraRepositoryProvider),
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

// Etapa 15 — "Generar PDF de dispersión" (control interno para ejecutar
// transferencias bancarias de una Nómina Cerrada/Pagada) — mismo
// criterio que "Generar recibo PDF": 100% regenerable desde la BD,
// nunca un Attachment.
final nominaDispersionPdfRendererProvider = Provider<NominaDispersionPdfRenderer>((ref) => NominaDispersionPdfRenderer());

final generarNominaDispersionPdfUseCaseProvider = Provider<GenerarNominaDispersionPdfUseCase>((ref) {
  return GenerarNominaDispersionPdfUseCase(
    ref.watch(nominaRepositoryProvider),
    ref.watch(attachmentStorageProvider),
    ref.watch(appPathsProvider).nominaDispersionDir,
    ref.watch(nominaDispersionPdfRendererProvider),
  );
});
