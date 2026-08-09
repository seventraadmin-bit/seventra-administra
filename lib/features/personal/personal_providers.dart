import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../organizacion/organizacion_providers.dart';
import 'data/repositories/empleado_repository_impl.dart';
import 'domain/repositories/empleado_repository.dart';
import 'domain/usecases/actualizar_fotografia_empleado_usecase.dart';
import 'domain/usecases/adjuntar_documento_empleado_usecase.dart';
import 'domain/usecases/cambiar_estatus_empleado_usecase.dart';
import 'domain/usecases/corregir_empleado_usecase.dart';
import 'domain/usecases/crear_empleado_usecase.dart';
import 'domain/usecases/empleado_validator.dart';
import 'domain/usecases/guardar_domicilio_empleado_usecase.dart';

/// Providers del dominio Personal (Etapa 5A) — nace aquí, separado de
/// `organizacion`/`comercial`/`finanzas` (mismo criterio que la
/// Resolución B de Marlon para `finanzas`, 4J.1).
final empleadoRepositoryProvider = Provider<EmpleadoRepository>((ref) {
  return EmpleadoRepositoryImpl(ref.watch(appDatabaseProvider));
});

final empleadoValidatorProvider = Provider<EmpleadoValidator>((ref) {
  return const EmpleadoValidator();
});

final crearEmpleadoUseCaseProvider = Provider<CrearEmpleadoUseCase>((ref) {
  return CrearEmpleadoUseCase(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(generarCodigoUseCaseProvider),
    ref.watch(empleadoValidatorProvider),
  );
});

final corregirEmpleadoUseCaseProvider = Provider<CorregirEmpleadoUseCase>((ref) {
  return CorregirEmpleadoUseCase(ref.watch(empleadoRepositoryProvider), ref.watch(empleadoValidatorProvider));
});

final cambiarEstatusEmpleadoUseCaseProvider = Provider<CambiarEstatusEmpleadoUseCase>((ref) {
  return CambiarEstatusEmpleadoUseCase(ref.watch(empleadoRepositoryProvider));
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
