import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../organizacion/organizacion_providers.dart';
import 'data/pdf/ficha_tecnica_pdf_renderer.dart';
import 'data/repositories/asignacion_servicio_repository_impl.dart';
import 'data/repositories/empleado_repository_impl.dart';
import 'data/repositories/ficha_tecnica_empleado_repository_impl.dart';
import 'domain/repositories/asignacion_servicio_repository.dart';
import 'domain/repositories/empleado_repository.dart';
import 'domain/repositories/ficha_tecnica_empleado_repository.dart';
import 'domain/usecases/actualizar_fotografia_empleado_usecase.dart';
import 'domain/usecases/adjuntar_documento_empleado_usecase.dart';
import 'domain/usecases/asignacion_servicio_validator.dart';
import 'domain/usecases/asignar_empleado_servicio_usecase.dart';
import 'domain/usecases/cambiar_servicio_empleado_usecase.dart';
import 'domain/usecases/cambiar_vigencia_sueldo_asignacion_usecase.dart';
import 'domain/usecases/corregir_empleado_usecase.dart';
import 'domain/usecases/crear_empleado_usecase.dart';
import 'domain/usecases/empleado_validator.dart';
import 'domain/usecases/generar_ficha_tecnica_empleado_usecase.dart';
import 'domain/usecases/guardar_domicilio_empleado_usecase.dart';
import 'domain/usecases/registrar_antidoping_usecase.dart';
import 'domain/usecases/registrar_baja_laboral_usecase.dart';
import 'domain/usecases/registrar_estudio_socioeconomico_usecase.dart';
import 'domain/usecases/registrar_perfil_psicologico_usecase.dart';
import 'domain/usecases/registrar_reingreso_usecase.dart';
import 'domain/usecases/retirar_empleado_servicio_usecase.dart';

/// Providers del dominio Personal (Etapa 5A) — nace aquí, separado de
/// `organizacion`/`comercial`/`finanzas` (mismo criterio que la
/// Resolución B de Marlon para `finanzas`, 4J.1).
final asignacionServicioRepositoryProvider = Provider<AsignacionServicioRepository>((ref) {
  return AsignacionServicioRepositoryImpl(ref.watch(appDatabaseProvider));
});

final asignacionServicioValidatorProvider = Provider<AsignacionServicioValidator>((ref) {
  return const AsignacionServicioValidator();
});

final empleadoRepositoryProvider = Provider<EmpleadoRepository>((ref) {
  return EmpleadoRepositoryImpl(ref.watch(appDatabaseProvider), ref.watch(asignacionServicioRepositoryProvider));
});

final empleadoValidatorProvider = Provider<EmpleadoValidator>((ref) {
  return const EmpleadoValidator();
});

final crearEmpleadoUseCaseProvider = Provider<CrearEmpleadoUseCase>((ref) {
  return CrearEmpleadoUseCase(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(generarNumeroUseCaseProvider),
    ref.watch(empleadoValidatorProvider),
    ref.watch(servicioRepositoryProvider),
  );
});

final asignarEmpleadoServicioUseCaseProvider = Provider<AsignarEmpleadoServicioUseCase>((ref) {
  return AsignarEmpleadoServicioUseCase(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(asignacionServicioRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
    ref.watch(asignacionServicioValidatorProvider),
  );
});

final cambiarServicioEmpleadoUseCaseProvider = Provider<CambiarServicioEmpleadoUseCase>((ref) {
  return CambiarServicioEmpleadoUseCase(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(asignacionServicioRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
    ref.watch(asignacionServicioValidatorProvider),
  );
});

final retirarEmpleadoServicioUseCaseProvider = Provider<RetirarEmpleadoServicioUseCase>((ref) {
  return RetirarEmpleadoServicioUseCase(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(asignacionServicioRepositoryProvider),
    ref.watch(asignacionServicioValidatorProvider),
  );
});

final cambiarVigenciaSueldoAsignacionUseCaseProvider = Provider<CambiarVigenciaSueldoAsignacionUseCase>((ref) {
  return CambiarVigenciaSueldoAsignacionUseCase(
    ref.watch(asignacionServicioRepositoryProvider),
    ref.watch(asignacionServicioValidatorProvider),
  );
});

final corregirEmpleadoUseCaseProvider = Provider<CorregirEmpleadoUseCase>((ref) {
  return CorregirEmpleadoUseCase(ref.watch(empleadoRepositoryProvider), ref.watch(empleadoValidatorProvider));
});

final registrarBajaLaboralUseCaseProvider = Provider<RegistrarBajaLaboralUseCase>((ref) {
  return RegistrarBajaLaboralUseCase(ref.watch(empleadoRepositoryProvider), ref.watch(empleadoValidatorProvider));
});

final registrarReingresoUseCaseProvider = Provider<RegistrarReingresoUseCase>((ref) {
  return RegistrarReingresoUseCase(ref.watch(empleadoRepositoryProvider), ref.watch(empleadoValidatorProvider));
});

final actualizarFotografiaEmpleadoUseCaseProvider = Provider<ActualizarFotografiaEmpleadoUseCase>((ref) {
  return ActualizarFotografiaEmpleadoUseCase(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(attachmentRepositoryProvider),
    ref.watch(attachmentStorageProvider),
  );
});

final guardarDomicilioEmpleadoUseCaseProvider = Provider<GuardarDomicilioEmpleadoUseCase>((ref) {
  return GuardarDomicilioEmpleadoUseCase(ref.watch(empleadoRepositoryProvider));
});

final adjuntarDocumentoEmpleadoUseCaseProvider = Provider<AdjuntarDocumentoEmpleadoUseCase>((ref) {
  return AdjuntarDocumentoEmpleadoUseCase(ref.watch(empleadoRepositoryProvider), ref.watch(attachmentStorageProvider));
});

final registrarPerfilPsicologicoUseCaseProvider = Provider<RegistrarPerfilPsicologicoUseCase>((ref) {
  return RegistrarPerfilPsicologicoUseCase(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(attachmentStorageProvider),
    ref.watch(empleadoValidatorProvider),
  );
});

final registrarEstudioSocioeconomicoUseCaseProvider = Provider<RegistrarEstudioSocioeconomicoUseCase>((ref) {
  return RegistrarEstudioSocioeconomicoUseCase(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(attachmentStorageProvider),
    ref.watch(empleadoValidatorProvider),
  );
});

final registrarAntidopingUseCaseProvider = Provider<RegistrarAntidopingUseCase>((ref) {
  return RegistrarAntidopingUseCase(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(attachmentStorageProvider),
    ref.watch(empleadoValidatorProvider),
  );
});

final fichaTecnicaEmpleadoRepositoryProvider = Provider<FichaTecnicaEmpleadoRepository>((ref) {
  return FichaTecnicaEmpleadoRepositoryImpl(ref.watch(appDatabaseProvider));
});

final fichaTecnicaPdfRendererProvider = Provider<FichaTecnicaPdfRenderer>((ref) {
  return FichaTecnicaPdfRenderer();
});

final generarFichaTecnicaEmpleadoUseCaseProvider = Provider<GenerarFichaTecnicaEmpleadoUseCase>((ref) {
  return GenerarFichaTecnicaEmpleadoUseCase(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(asignacionServicioRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
    ref.watch(puestoRepositoryProvider),
    ref.watch(catalogoRepositoryProvider),
    ref.watch(empresaRepositoryProvider),
    ref.watch(attachmentRepositoryProvider),
    ref.watch(attachmentStorageProvider),
    ref.watch(fichaTecnicaEmpleadoRepositoryProvider),
    ref.watch(generarCodigoUseCaseProvider),
    ref.watch(fichaTecnicaPdfRendererProvider),
  );
});
