import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/permissions/authorization_service.dart';
import '../../core/validation/direccion_validator.dart' show DireccionBorrador;
import '../organizacion/organizacion_providers.dart';
import '../usuarios/presentation/sesion_controller.dart';
import '../usuarios/usuarios_providers.dart';
import 'data/pdf/ficha_tecnica_pdf_renderer.dart';
import 'data/tables/asignacion_servicio_table.dart' show MotivoTerminoAsignacion;
import 'data/tables/empleado_table.dart';
import 'data/repositories/asignacion_servicio_repository_impl.dart';
import 'data/repositories/empleado_repository_impl.dart';
import 'data/repositories/ficha_tecnica_empleado_repository_impl.dart';
import 'data/repositories/vacante_operativa_repository_impl.dart';
import 'domain/repositories/asignacion_servicio_repository.dart';
import 'domain/repositories/empleado_repository.dart';
import 'domain/repositories/ficha_tecnica_empleado_repository.dart';
import 'domain/repositories/vacante_operativa_repository.dart';
import 'domain/usecases/actualizar_fotografia_empleado_usecase.dart';
import 'domain/usecases/adjuntar_documento_empleado_usecase.dart';
import 'domain/usecases/asignacion_servicio_validator.dart';
import 'domain/usecases/asignar_empleado_servicio_usecase.dart';
import 'domain/usecases/cambiar_servicio_empleado_usecase.dart';
import 'domain/usecases/cambiar_vigencia_sueldo_asignacion_usecase.dart';
import 'domain/usecases/corregir_empleado_usecase.dart';
import 'domain/usecases/crear_empleado_usecase.dart';
import 'domain/usecases/obtener_plantilla_personal_usecase.dart';
import 'domain/usecases/obtener_rotacion_personal_usecase.dart';
import 'domain/usecases/eliminar_empleado_fisicamente_usecase.dart';
import 'domain/usecases/empleado_validator.dart';
import 'domain/usecases/generar_ficha_tecnica_empleado_usecase.dart';
import 'domain/usecases/guardar_domicilio_empleado_usecase.dart';
import 'domain/usecases/registrar_antidoping_usecase.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart' show asignacionRepositoryProvider;
import 'package:riseg_one/features/vehiculos/vehiculos_providers.dart' show asignacionVehiculoRepositoryProvider;
import 'package:riseg_one/features/descuentos_personal/descuentos_personal_providers.dart' show registrarDescuentoProgramadoUseCaseProvider;
import 'package:riseg_one/core/database/app_database.dart' show EmpleadoData;
import 'data/repositories/conciliacion_baja_repository_impl.dart';
import 'domain/repositories/conciliacion_baja_repository.dart';
import 'domain/usecases/conciliar_baja_empleado_usecase.dart';
import 'domain/usecases/registrar_baja_laboral_usecase.dart';
import 'domain/usecases/registrar_estudio_socioeconomico_usecase.dart';
import 'domain/usecases/registrar_perfil_psicologico_usecase.dart';
import 'domain/usecases/registrar_reingreso_usecase.dart';
import 'domain/usecases/regularizar_perfil_asignacion_usecase.dart';
import 'domain/usecases/retirar_empleado_servicio_usecase.dart';

/// Providers del dominio Personal (Etapa 5A) — nace aquí, separado de
/// `organizacion`/`comercial`/`finanzas` (mismo criterio que la
/// Resolución B de Marlon para `finanzas`, 4J.1).
final asignacionServicioRepositoryProvider = Provider<AsignacionServicioRepository>((ref) {
  return AsignacionServicioRepositoryImpl(ref.watch(appDatabaseProvider));
});

/// Bitácora de vacantes operativas (Etapa 15, rediseño del Dashboard) —
/// ver el doc comment de `VacanteOperativa`. Escrita internamente por
/// `AsignacionServicioRepositoryImpl` (compuesta ahí sin inyección, ver
/// su propio doc comment); expuesta aquí como provider independiente
/// para el lado de LECTURA (Dashboard).
final vacanteOperativaRepositoryProvider = Provider<VacanteOperativaRepository>((ref) {
  return VacanteOperativaRepositoryImpl(ref.watch(appDatabaseProvider));
});

final asignacionServicioValidatorProvider = Provider<AsignacionServicioValidator>((ref) {
  return const AsignacionServicioValidator();
});

// Deliberadamente SIN `attachmentStorage` (a diferencia de
// `documentoPorEmitirRepositoryProvider`): este provider lo observa
// (`watch`, no `read`) TODA pantalla que toca Personal, incluido el
// propio Dashboard vía `obtenerEmpleadosBajaConPendienteUseCaseProvider`
// — encadenar aquí `attachmentStorageProvider` (que requiere
// `appPathsProvider`, resuelto solo en bootstrap real) rompería
// cualquier prueba de Dashboard/Personal que no lo sobreescriba
// explícitamente, aunque nunca vaya a eliminar físicamente a nadie
// (Etapa 15, hallazgo real). La eliminación física (única consumidora
// real de `AttachmentStorage` en este dominio) construye su propia
// instancia de `EmpleadoRepositoryImpl` en
// `eliminarEmpleadoFisicamenteUseCaseProvider`, más abajo.
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
    ref.watch(servicioComercialRepositoryProvider),
  );
});

final asignarEmpleadoServicioUseCaseProvider = Provider<AsignarEmpleadoServicioUseCase>((ref) {
  return AsignarEmpleadoServicioUseCase(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(asignacionServicioRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
    ref.watch(servicioComercialRepositoryProvider),
    ref.watch(asignacionServicioValidatorProvider),
  );
});

final cambiarServicioEmpleadoUseCaseProvider = Provider<CambiarServicioEmpleadoUseCase>((ref) {
  return CambiarServicioEmpleadoUseCase(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(asignacionServicioRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
    ref.watch(servicioComercialRepositoryProvider),
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
  return CorregirEmpleadoUseCase(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(empleadoValidatorProvider),
    ref.watch(asignacionServicioRepositoryProvider),
  );
});

final registrarBajaLaboralUseCaseProvider = Provider<RegistrarBajaLaboralUseCase>((ref) {
  return RegistrarBajaLaboralUseCase(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(empleadoValidatorProvider),
    ref.watch(asignacionRepositoryProvider),
    ref.watch(asignacionVehiculoRepositoryProvider),
    // Etapa 3B: el invariante "nunca sin Maestro activo" se comprueba
    // aquí, antes de escribir, porque la baja desactiva la cuenta.
    usuarioRepository: ref.watch(usuarioRepositoryProvider),
  );
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

// Etapa 0 (auditoría de consistencia transversal — corrección de un
// hueco real de autorización): estas 9 operaciones del expediente de
// Personal se invocaban desde sus diálogos directo sobre el use case
// crudo, sin ningún `autorizarUseCase` en toda la cadena. Mismo código
// ya usado para `corregirEmpleado` (`personal.modificar`) — todas son
// mutaciones del expediente del empleado, nunca un código nuevo.
typedef AsignarEmpleadoServicioAutorizado = Future<AsignarEmpleadoServicioResultado> Function({
  required String empleadoId,
  required String servicioId,
  required DateTime fechaInicio,
  String? turnoId,
  String? lineaComercialId,
  String? observaciones,
  int? sueldoMensual,
  int? bonoMensual,
});

final asignarEmpleadoServicioAutorizadoProvider = Provider<AsignarEmpleadoServicioAutorizado>((ref) {
  return ({
    required String empleadoId,
    required String servicioId,
    required DateTime fechaInicio,
    String? turnoId,
    String? lineaComercialId,
    String? observaciones,
    int? sueldoMensual,
    int? bonoMensual,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'personal.modificar',
      () => ref.read(asignarEmpleadoServicioUseCaseProvider).ejecutar(
            empleadoId: empleadoId,
            servicioId: servicioId,
            fechaInicio: fechaInicio,
            turnoId: turnoId,
            lineaComercialId: lineaComercialId,
            observaciones: observaciones,
            sueldoMensual: sueldoMensual,
            bonoMensual: bonoMensual,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      AsignarEmpleadoServicioErrorInesperado.new,
    );
  };
});

typedef CambiarServicioEmpleadoAutorizado = Future<CambiarServicioEmpleadoResultado> Function({
  required String empleadoId,
  required String nuevoServicioId,
  required DateTime fecha,
  String? turnoId,
  String? lineaComercialId,
  String? observaciones,
  int? sueldoMensual,
  int? bonoMensual,
});

final cambiarServicioEmpleadoAutorizadoProvider = Provider<CambiarServicioEmpleadoAutorizado>((ref) {
  return ({
    required String empleadoId,
    required String nuevoServicioId,
    required DateTime fecha,
    String? turnoId,
    String? lineaComercialId,
    String? observaciones,
    int? sueldoMensual,
    int? bonoMensual,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'personal.modificar',
      () => ref.read(cambiarServicioEmpleadoUseCaseProvider).ejecutar(
            empleadoId: empleadoId,
            nuevoServicioId: nuevoServicioId,
            fecha: fecha,
            turnoId: turnoId,
            lineaComercialId: lineaComercialId,
            observaciones: observaciones,
            sueldoMensual: sueldoMensual,
            bonoMensual: bonoMensual,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CambiarServicioEmpleadoErrorInesperado.new,
    );
  };
});

typedef RetirarEmpleadoServicioAutorizado = Future<RetirarEmpleadoServicioResultado> Function({
  required String empleadoId,
  required DateTime fechaTermino,
  required MotivoTerminoAsignacion motivo,
  String? observaciones,
});

final retirarEmpleadoServicioAutorizadoProvider = Provider<RetirarEmpleadoServicioAutorizado>((ref) {
  return ({
    required String empleadoId,
    required DateTime fechaTermino,
    required MotivoTerminoAsignacion motivo,
    String? observaciones,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'personal.modificar',
      () => ref.read(retirarEmpleadoServicioUseCaseProvider).ejecutar(
            empleadoId: empleadoId,
            fechaTermino: fechaTermino,
            motivo: motivo,
            observaciones: observaciones,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      RetirarEmpleadoServicioErrorInesperado.new,
    );
  };
});

typedef ActualizarFotografiaEmpleadoAutorizado = Future<ActualizarFotografiaEmpleadoResultado> Function({
  required String empleadoId,
  required String sourceFilePath,
  required String originalFileName,
  required String mimeType,
});

final actualizarFotografiaEmpleadoAutorizadoProvider = Provider<ActualizarFotografiaEmpleadoAutorizado>((ref) {
  return ({
    required String empleadoId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'personal.modificar',
      () => ref.read(actualizarFotografiaEmpleadoUseCaseProvider).ejecutar(
            empleadoId: empleadoId,
            sourceFilePath: sourceFilePath,
            originalFileName: originalFileName,
            mimeType: mimeType,
          ),
      ActualizarFotografiaEmpleadoErrorInesperado.new,
    );
  };
});

typedef GuardarDomicilioEmpleadoAutorizado = Future<GuardarDomicilioEmpleadoResultado> Function({
  required String empleadoId,
  required DireccionBorrador? domicilio,
});

final guardarDomicilioEmpleadoAutorizadoProvider = Provider<GuardarDomicilioEmpleadoAutorizado>((ref) {
  return ({required String empleadoId, required DireccionBorrador? domicilio}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'personal.modificar',
      () => ref.read(guardarDomicilioEmpleadoUseCaseProvider).ejecutar(
            empleadoId: empleadoId,
            domicilio: domicilio,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      GuardarDomicilioEmpleadoErrorInesperado.new,
    );
  };
});

typedef AdjuntarDocumentoEmpleadoAutorizado = Future<AdjuntarDocumentoEmpleadoResultado> Function({
  required String empleadoId,
  required CategoriaDocumentoEmpleado categoria,
  required String sourceFilePath,
  required String originalFileName,
  required String mimeType,
});

final adjuntarDocumentoEmpleadoAutorizadoProvider = Provider<AdjuntarDocumentoEmpleadoAutorizado>((ref) {
  return ({
    required String empleadoId,
    required CategoriaDocumentoEmpleado categoria,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'personal.modificar',
      () => ref.read(adjuntarDocumentoEmpleadoUseCaseProvider).ejecutar(
            empleadoId: empleadoId,
            categoria: categoria,
            sourceFilePath: sourceFilePath,
            originalFileName: originalFileName,
            mimeType: mimeType,
          ),
      AdjuntarDocumentoEmpleadoErrorInesperado.new,
    );
  };
});

typedef RegistrarPerfilPsicologicoAutorizado = Future<RegistrarPerfilPsicologicoResultado> Function({
  required String empleadoId,
  required DateTime fecha,
  String? resumen,
  String? observaciones,
  String? sourceFilePath,
  String? originalFileName,
  String? mimeType,
});

final registrarPerfilPsicologicoAutorizadoProvider = Provider<RegistrarPerfilPsicologicoAutorizado>((ref) {
  return ({
    required String empleadoId,
    required DateTime fecha,
    String? resumen,
    String? observaciones,
    String? sourceFilePath,
    String? originalFileName,
    String? mimeType,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'personal.modificar',
      () => ref.read(registrarPerfilPsicologicoUseCaseProvider).ejecutar(
            empleadoId: empleadoId,
            fecha: fecha,
            resumen: resumen,
            observaciones: observaciones,
            sourceFilePath: sourceFilePath,
            originalFileName: originalFileName,
            mimeType: mimeType,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      RegistrarPerfilPsicologicoErrorInesperado.new,
    );
  };
});

typedef RegistrarEstudioSocioeconomicoAutorizado = Future<RegistrarEstudioSocioeconomicoResultado> Function({
  required String empleadoId,
  required DateTime fecha,
  String? resumen,
  String? observaciones,
  String? sourceFilePath,
  String? originalFileName,
  String? mimeType,
});

final registrarEstudioSocioeconomicoAutorizadoProvider = Provider<RegistrarEstudioSocioeconomicoAutorizado>((ref) {
  return ({
    required String empleadoId,
    required DateTime fecha,
    String? resumen,
    String? observaciones,
    String? sourceFilePath,
    String? originalFileName,
    String? mimeType,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'personal.modificar',
      () => ref.read(registrarEstudioSocioeconomicoUseCaseProvider).ejecutar(
            empleadoId: empleadoId,
            fecha: fecha,
            resumen: resumen,
            observaciones: observaciones,
            sourceFilePath: sourceFilePath,
            originalFileName: originalFileName,
            mimeType: mimeType,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      RegistrarEstudioSocioeconomicoErrorInesperado.new,
    );
  };
});

typedef RegistrarAntidopingAutorizado = Future<RegistrarAntidopingResultado> Function({
  required String empleadoId,
  required DateTime fecha,
  required ResultadoSustanciaAntidoping amp,
  required ResultadoSustanciaAntidoping bzd,
  required ResultadoSustanciaAntidoping coc,
  required ResultadoSustanciaAntidoping met,
  required ResultadoSustanciaAntidoping opi,
  String? observaciones,
  String? sourceFilePath,
  String? originalFileName,
  String? mimeType,
});

final registrarAntidopingAutorizadoProvider = Provider<RegistrarAntidopingAutorizado>((ref) {
  return ({
    required String empleadoId,
    required DateTime fecha,
    required ResultadoSustanciaAntidoping amp,
    required ResultadoSustanciaAntidoping bzd,
    required ResultadoSustanciaAntidoping coc,
    required ResultadoSustanciaAntidoping met,
    required ResultadoSustanciaAntidoping opi,
    String? observaciones,
    String? sourceFilePath,
    String? originalFileName,
    String? mimeType,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'personal.modificar',
      () => ref.read(registrarAntidopingUseCaseProvider).ejecutar(
            empleadoId: empleadoId,
            fecha: fecha,
            amp: amp,
            bzd: bzd,
            coc: coc,
            met: met,
            opi: opi,
            observaciones: observaciones,
            sourceFilePath: sourceFilePath,
            originalFileName: originalFileName,
            mimeType: mimeType,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      RegistrarAntidopingErrorInesperado.new,
    );
  };
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

// --- Fachadas de aplicación autorizadas (Etapa 11C) ---
//
// Personal no tiene un Controller de escritura (los diálogos llaman los
// UseCase providers directo) — así que estas fachadas son el punto de
// entrada de aplicación más bajo y reutilizable que representa cada
// operación protegida. Se exponen como `Provider<Función>` (no como
// función suelta que reciba `Ref`) a propósito: `WidgetRef` (que tienen
// los diálogos) y `ProviderContainer` (que usan las pruebas) no
// comparten una interfaz común más allá de `.read(provider)`, así que
// leer el Provider es lo único que necesita funcionar igual en ambos
// lados — el cierre ya trae su propio `ref` capturado. `autorizarUseCase`
// es el único punto del proyecto que evalúa el permiso — nunca se repite
// el chequeo en el diálogo ni en el UseCase.

typedef CrearEmpleadoAutorizado = Future<CrearEmpleadoResultado> Function({
  required String nombres,
  required String apellidoPaterno,
  String? apellidoMaterno,
  required SexoEmpleado sexo,
  required DateTime fechaNacimiento,
  required String curp,
  required String rfc,
  String? codigoPostalFiscal,
  required String nss,
  required EstadoCivilEmpleado estadoCivil,
  String nacionalidad,
  String? telefono,
  String? correoElectronico,
  String? contactoEmergenciaNombre,
  String? telefonoEmergencia,
  String? parentescoEmergencia,
  required DateTime fechaIngreso,
  String? puestoId,
  String? empresaId,
  String? servicioId,
  String? turnoId,
  String? lineaComercialId,
  int? sueldoMensualAsignacion,
  int? bonoMensualAsignacion,
  String? sucursalId,
  String? bancoId,
  String? bancoOtroDescripcion,
  String? numeroCuentaTarjeta,
  String? clabe,
  int? sueldoMensualAdministrativo,
  int? bonoMensualAdministrativo,
  String? observaciones,
  NivelEstudiosEmpleado? nivelEstudios,
  String? observacionesEscolaridad,
  required int aniosExperienciaSeguridad,
  int? mesesExperienciaAdicionales,
  String? ultimoPuestoDesempenado,
  String? resumenExperiencia,
  String? observacionesExperiencia,
});

final crearEmpleadoAutorizadoProvider = Provider<CrearEmpleadoAutorizado>((ref) {
  return ({
    required String nombres,
    required String apellidoPaterno,
    String? apellidoMaterno,
    required SexoEmpleado sexo,
    required DateTime fechaNacimiento,
    required String curp,
    required String rfc,
    String? codigoPostalFiscal,
    required String nss,
    required EstadoCivilEmpleado estadoCivil,
    String nacionalidad = 'Mexicana',
    String? telefono,
    String? correoElectronico,
    String? contactoEmergenciaNombre,
    String? telefonoEmergencia,
    String? parentescoEmergencia,
    required DateTime fechaIngreso,
    String? puestoId,
    String? empresaId,
    String? servicioId,
    String? turnoId,
    String? lineaComercialId,
    int? sueldoMensualAsignacion,
    int? bonoMensualAsignacion,
    String? sucursalId,
    String? bancoId,
    String? bancoOtroDescripcion,
    String? numeroCuentaTarjeta,
    String? clabe,
    int? sueldoMensualAdministrativo,
    int? bonoMensualAdministrativo,
    String? observaciones,
    NivelEstudiosEmpleado? nivelEstudios,
    String? observacionesEscolaridad,
    required int aniosExperienciaSeguridad,
    int? mesesExperienciaAdicionales,
    String? ultimoPuestoDesempenado,
    String? resumenExperiencia,
    String? observacionesExperiencia,
  }) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'personal.crear',
      () => ref.read(crearEmpleadoUseCaseProvider).ejecutar(
            nombres: nombres,
            apellidoPaterno: apellidoPaterno,
            apellidoMaterno: apellidoMaterno,
            sexo: sexo,
            fechaNacimiento: fechaNacimiento,
            curp: curp,
            rfc: rfc,
            codigoPostalFiscal: codigoPostalFiscal,
            nss: nss,
            estadoCivil: estadoCivil,
            nacionalidad: nacionalidad,
            telefono: telefono,
            correoElectronico: correoElectronico,
            contactoEmergenciaNombre: contactoEmergenciaNombre,
            telefonoEmergencia: telefonoEmergencia,
            parentescoEmergencia: parentescoEmergencia,
            fechaIngreso: fechaIngreso,
            puestoId: puestoId,
            empresaId: empresaId,
            servicioId: servicioId,
            turnoId: turnoId,
            lineaComercialId: lineaComercialId,
            sueldoMensualAsignacion: sueldoMensualAsignacion,
            bonoMensualAsignacion: bonoMensualAsignacion,
            sucursalId: sucursalId,
            bancoId: bancoId,
            bancoOtroDescripcion: bancoOtroDescripcion,
            numeroCuentaTarjeta: numeroCuentaTarjeta,
            clabe: clabe,
            sueldoMensualAdministrativo: sueldoMensualAdministrativo,
            bonoMensualAdministrativo: bonoMensualAdministrativo,
            observaciones: observaciones,
            nivelEstudios: nivelEstudios,
            observacionesEscolaridad: observacionesEscolaridad,
            aniosExperienciaSeguridad: aniosExperienciaSeguridad,
            mesesExperienciaAdicionales: mesesExperienciaAdicionales,
            ultimoPuestoDesempenado: ultimoPuestoDesempenado,
            resumenExperiencia: resumenExperiencia,
            observacionesExperiencia: observacionesExperiencia,
            actorUsuarioId: actorUsuarioId,
          ),
      CrearEmpleadoErrorInesperado.new,
    );
  };
});

typedef CorregirEmpleadoAutorizado = Future<CorregirEmpleadoResultado> Function({
  required String empleadoId,
  String? nombres,
  String? apellidoPaterno,
  String? apellidoMaterno,
  SexoEmpleado? sexo,
  DateTime? fechaNacimiento,
  String? curp,
  String? rfc,
  String? codigoPostalFiscal,
  bool limpiarCodigoPostalFiscal,
  String? nss,
  EstadoCivilEmpleado? estadoCivil,
  String? nacionalidad,
  String? telefono,
  String? correoElectronico,
  String? contactoEmergenciaNombre,
  String? telefonoEmergencia,
  String? parentescoEmergencia,
  DateTime? fechaIngreso,
  String? puestoId,
  bool limpiarPuesto,
  String? empresaId,
  bool limpiarEmpresa,
  String? sucursalId,
  bool limpiarSucursal,
  String? bancoId,
  bool limpiarBanco,
  String? bancoOtroDescripcion,
  bool limpiarBancoOtroDescripcion,
  String? numeroCuentaTarjeta,
  bool limpiarNumeroCuentaTarjeta,
  String? clabe,
  bool limpiarClabe,
  int? sueldoMensualAdministrativo,
  bool limpiarSueldoMensualAdministrativo,
  int? bonoMensualAdministrativo,
  bool limpiarBonoMensualAdministrativo,
  String? observaciones,
  NivelEstudiosEmpleado? nivelEstudios,
  String? observacionesEscolaridad,
  int? aniosExperienciaSeguridad,
  int? mesesExperienciaAdicionales,
  String? ultimoPuestoDesempenado,
  String? resumenExperiencia,
  String? observacionesExperiencia,
  required String motivo,
});

final corregirEmpleadoAutorizadoProvider = Provider<CorregirEmpleadoAutorizado>((ref) {
  return ({
    required String empleadoId,
    String? nombres,
    String? apellidoPaterno,
    String? apellidoMaterno,
    SexoEmpleado? sexo,
    DateTime? fechaNacimiento,
    String? curp,
    String? rfc,
    String? codigoPostalFiscal,
    bool limpiarCodigoPostalFiscal = false,
    String? nss,
    EstadoCivilEmpleado? estadoCivil,
    String? nacionalidad,
    String? telefono,
    String? correoElectronico,
    String? contactoEmergenciaNombre,
    String? telefonoEmergencia,
    String? parentescoEmergencia,
    DateTime? fechaIngreso,
    String? puestoId,
    bool limpiarPuesto = false,
    String? empresaId,
    bool limpiarEmpresa = false,
    String? sucursalId,
    bool limpiarSucursal = false,
    String? bancoId,
    bool limpiarBanco = false,
    String? bancoOtroDescripcion,
    bool limpiarBancoOtroDescripcion = false,
    String? numeroCuentaTarjeta,
    bool limpiarNumeroCuentaTarjeta = false,
    String? clabe,
    bool limpiarClabe = false,
    int? sueldoMensualAdministrativo,
    bool limpiarSueldoMensualAdministrativo = false,
    int? bonoMensualAdministrativo,
    bool limpiarBonoMensualAdministrativo = false,
    String? observaciones,
    NivelEstudiosEmpleado? nivelEstudios,
    String? observacionesEscolaridad,
    int? aniosExperienciaSeguridad,
    int? mesesExperienciaAdicionales,
    String? ultimoPuestoDesempenado,
    String? resumenExperiencia,
    String? observacionesExperiencia,
    required String motivo,
  }) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'personal.modificar',
      () => ref.read(corregirEmpleadoUseCaseProvider).ejecutar(
            empleadoId: empleadoId,
            nombres: nombres,
            apellidoPaterno: apellidoPaterno,
            apellidoMaterno: apellidoMaterno,
            sexo: sexo,
            fechaNacimiento: fechaNacimiento,
            curp: curp,
            rfc: rfc,
            codigoPostalFiscal: codigoPostalFiscal,
            limpiarCodigoPostalFiscal: limpiarCodigoPostalFiscal,
            nss: nss,
            estadoCivil: estadoCivil,
            nacionalidad: nacionalidad,
            telefono: telefono,
            correoElectronico: correoElectronico,
            contactoEmergenciaNombre: contactoEmergenciaNombre,
            telefonoEmergencia: telefonoEmergencia,
            parentescoEmergencia: parentescoEmergencia,
            fechaIngreso: fechaIngreso,
            puestoId: puestoId,
            limpiarPuesto: limpiarPuesto,
            empresaId: empresaId,
            limpiarEmpresa: limpiarEmpresa,
            sucursalId: sucursalId,
            limpiarSucursal: limpiarSucursal,
            bancoId: bancoId,
            limpiarBanco: limpiarBanco,
            bancoOtroDescripcion: bancoOtroDescripcion,
            limpiarBancoOtroDescripcion: limpiarBancoOtroDescripcion,
            numeroCuentaTarjeta: numeroCuentaTarjeta,
            limpiarNumeroCuentaTarjeta: limpiarNumeroCuentaTarjeta,
            clabe: clabe,
            limpiarClabe: limpiarClabe,
            sueldoMensualAdministrativo: sueldoMensualAdministrativo,
            limpiarSueldoMensualAdministrativo: limpiarSueldoMensualAdministrativo,
            bonoMensualAdministrativo: bonoMensualAdministrativo,
            limpiarBonoMensualAdministrativo: limpiarBonoMensualAdministrativo,
            observaciones: observaciones,
            nivelEstudios: nivelEstudios,
            observacionesEscolaridad: observacionesEscolaridad,
            aniosExperienciaSeguridad: aniosExperienciaSeguridad,
            mesesExperienciaAdicionales: mesesExperienciaAdicionales,
            ultimoPuestoDesempenado: ultimoPuestoDesempenado,
            resumenExperiencia: resumenExperiencia,
            observacionesExperiencia: observacionesExperiencia,
            motivo: motivo,
            actorUsuarioId: actorUsuarioId,
          ),
      CorregirEmpleadoErrorInesperado.new,
    );
  };
});

typedef RegistrarBajaLaboralAutorizado = Future<RegistrarBajaLaboralResultado> Function({
  required String empleadoId,
  required DateTime fechaBaja,
  required MotivoBajaEmpleado motivo,
  String? observaciones,
});

final registrarBajaLaboralAutorizadoProvider = Provider<RegistrarBajaLaboralAutorizado>((ref) {
  return ({
    required String empleadoId,
    required DateTime fechaBaja,
    required MotivoBajaEmpleado motivo,
    String? observaciones,
  }) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'personal.archivar',
      () => ref.read(registrarBajaLaboralUseCaseProvider).ejecutar(
            empleadoId: empleadoId,
            fechaBaja: fechaBaja,
            motivo: motivo,
            observaciones: observaciones,
            actorUsuarioId: actorUsuarioId,
          ),
      RegistrarBajaLaboralErrorInesperado.new,
    );
  };
});

typedef RegistrarReingresoAutorizado = Future<RegistrarReingresoResultado> Function({
  required String empleadoId,
  required DateTime fechaIngreso,
  String? puestoId,
  bool limpiarPuesto,
  String? sucursalId,
  bool limpiarSucursal,
});

final registrarReingresoAutorizadoProvider = Provider<RegistrarReingresoAutorizado>((ref) {
  return ({
    required String empleadoId,
    required DateTime fechaIngreso,
    String? puestoId,
    bool limpiarPuesto = false,
    String? sucursalId,
    bool limpiarSucursal = false,
  }) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'personal.archivar',
      () => ref.read(registrarReingresoUseCaseProvider).ejecutar(
            empleadoId: empleadoId,
            fechaIngreso: fechaIngreso,
            puestoId: puestoId,
            limpiarPuesto: limpiarPuesto,
            sucursalId: sucursalId,
            limpiarSucursal: limpiarSucursal,
            actorUsuarioId: actorUsuarioId,
          ),
      RegistrarReingresoErrorInesperado.new,
    );
  };
});

typedef CambiarVigenciaSueldoAsignacionAutorizado = Future<CambiarVigenciaSueldoAsignacionResultado> Function({
  required String asignacionServicioId,
  required int sueldoMensual,
  required int bonoMensual,
  required DateTime fechaInicioVigencia,
  String? observaciones,
});

final cambiarVigenciaSueldoAsignacionAutorizadoProvider = Provider<CambiarVigenciaSueldoAsignacionAutorizado>((ref) {
  return ({
    required String asignacionServicioId,
    required int sueldoMensual,
    required int bonoMensual,
    required DateTime fechaInicioVigencia,
    String? observaciones,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'personal.cambiarSueldo',
      () => ref.read(cambiarVigenciaSueldoAsignacionUseCaseProvider).ejecutar(
            asignacionServicioId: asignacionServicioId,
            sueldoMensual: sueldoMensual,
            bonoMensual: bonoMensual,
            fechaInicioVigencia: fechaInicioVigencia,
            observaciones: observaciones,
          ),
      CambiarVigenciaSueldoAsignacionErrorInesperado.new,
    );
  };
});

typedef GenerarFichaTecnicaEmpleadoAutorizado = Future<GenerarFichaTecnicaEmpleadoResultado> Function({
  required String empleadoId,
  Set<String> seccionesExcluidas,
});

// Etapa 1B (cierre de seguridad): antes gateada por `personal.crear` —
// sin razón real (confirmado por auditoría): generar la ficha técnica
// de un Empleado YA EXISTENTE no crea ningún Empleado, es una consulta/
// generación de documento sobre datos ya visibles en su expediente
// (gateado a su vez por `personal.ver`). Nunca toca la fila del
// Empleado — solo inserta un registro histórico de la ficha generada.
final generarFichaTecnicaEmpleadoAutorizadoProvider = Provider<GenerarFichaTecnicaEmpleadoAutorizado>((ref) {
  return ({
    required String empleadoId,
    Set<String> seccionesExcluidas = const {},
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'personal.ver',
      () => ref.read(generarFichaTecnicaEmpleadoUseCaseProvider).ejecutar(
            empleadoId: empleadoId,
            seccionesExcluidas: seccionesExcluidas,
          ),
      GenerarFichaTecnicaEmpleadoErrorInesperado.new,
    );
  };
});

// Eliminación física extraordinaria (Etapa 15) — facultad exclusiva del
// Usuario Maestro, mismo patrón exacto que Cliente/Servicio/Compra/
// Egreso/Documento por emitir (`exigirMaestro`, nunca
// `AuthorizationService.verificar`) — primer caso de `exigirMaestro` en
// el dominio Personal.
final eliminarEmpleadoFisicamenteUseCaseProvider = Provider<EliminarEmpleadoFisicamenteUseCase>((ref) {
  // Instancia propia (no `empleadoRepositoryProvider`) — ver el doc
  // comment de ese provider: solo aquí hace falta `AttachmentStorage`
  // para poder limpiar los archivos físicos (fotografía, documentos,
  // PDFs de fichas técnicas) cuando el Empleado se elimina.
  final repo = EmpleadoRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(asignacionServicioRepositoryProvider),
    attachmentStorage: ref.watch(attachmentStorageProvider),
  );
  return EliminarEmpleadoFisicamenteUseCase(repo);
});

typedef EliminarEmpleadoFisicamenteAutorizado = Future<EliminarEmpleadoFisicamenteResultado> Function({
  required String empleadoId,
  required String motivo,
});

final eliminarEmpleadoFisicamenteAutorizadoProvider = Provider<EliminarEmpleadoFisicamenteAutorizado>((ref) {
  return ({required String empleadoId, required String motivo}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(eliminarEmpleadoFisicamenteUseCaseProvider).ejecutar(
            empleadoId: empleadoId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      EliminarEmpleadoFisicamenteErrorInesperado.new,
    );
  };
});

// "Regularizar perfil de asignación" (Etapa 15, corrección del bug real
// de atribución histórica) — completa un `lineaComercialId` que quedó
// `NULL` en una asignación vigente (dato previo a Etapa 15). Facultad
// exclusiva del Usuario Maestro, mismo patrón `exigirMaestro` que
// eliminación física — corrige un dato de clasificación, no cualquier
// usuario debe poder reescribirlo.
final regularizarPerfilAsignacionServicioUseCaseProvider = Provider<RegularizarPerfilAsignacionServicioUseCase>((ref) {
  return RegularizarPerfilAsignacionServicioUseCase(
    ref.watch(asignacionServicioRepositoryProvider),
    ref.watch(servicioComercialRepositoryProvider),
  );
});

typedef RegularizarPerfilAsignacionAutorizado = Future<RegularizarPerfilAsignacionResultado> Function({
  required String asignacionServicioId,
  required String lineaComercialId,
});

final regularizarPerfilAsignacionAutorizadoProvider = Provider<RegularizarPerfilAsignacionAutorizado>((ref) {
  return ({required String asignacionServicioId, required String lineaComercialId}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(regularizarPerfilAsignacionServicioUseCaseProvider).ejecutar(
            asignacionServicioId: asignacionServicioId,
            lineaComercialId: lineaComercialId,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      RegularizarPerfilAsignacionErrorInesperado.new,
    );
  };
});

// --- Etapa "Plantilla operativa vs. administrativa" ---

/// Fuente de verdad ÚNICA de la composición de la plantilla — Dashboard,
/// Personal y Reportes la consumen; ninguno reimplementa la regla
/// Servicio=operativo / Sucursal=administrativo.
final obtenerPlantillaPersonalUseCaseProvider = Provider<ObtenerPlantillaPersonalUseCase>((ref) {
  return ObtenerPlantillaPersonalUseCase(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(asignacionServicioRepositoryProvider),
    ref.watch(puestoRepositoryProvider),
  );
});

/// Rotación reconstruida sobre ciclos laborales reales — métrica de
/// PERIODO, nunca snapshot (ver el doc comment del use case).
final obtenerRotacionPersonalUseCaseProvider = Provider<ObtenerRotacionPersonalUseCase>((ref) {
  return ObtenerRotacionPersonalUseCase(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(asignacionServicioRepositoryProvider),
  );
});

/// Conciliación de resguardos al dar de baja (schemaVersion 83).
final conciliacionBajaRepositoryProvider = Provider<ConciliacionBajaRepository>((ref) {
  return ConciliacionBajaRepositoryImpl(ref.watch(appDatabaseProvider));
});

final conciliarBajaEmpleadoUseCaseProvider = Provider<ConciliarBajaEmpleadoUseCase>((ref) {
  return ConciliarBajaEmpleadoUseCase(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(registrarBajaLaboralUseCaseProvider),
    ref.watch(asignacionRepositoryProvider),
    ref.watch(asignacionVehiculoRepositoryProvider),
    ref.watch(conciliacionBajaRepositoryProvider),
    ref.watch(registrarDescuentoProgramadoUseCaseProvider),
  );
});

typedef ConciliarBajaEmpleadoAutorizado = Future<ConciliarBajaEmpleadoResultado> Function({
  required String empleadoId,
  required DateTime fechaBaja,
  required MotivoBajaEmpleado motivo,
  String? observaciones,
  required List<ResolucionResguardo> resoluciones,
});

/// Gateado con `personal.archivar`, el MISMO permiso que ya protege la
/// baja laboral. Auditado antes de decidirlo: la conciliación no es una
/// facultad aparte, es la baja hecha bien. El control que Marlon pidió
/// —quién autoriza no recuperar o no cobrar— es un DATO (un empleado
/// administrativo por FK), no un permiso; crear un código nuevo daría
/// la apariencia de un control que en realidad ya vive en el dato.
final conciliarBajaEmpleadoAutorizadoProvider = Provider<ConciliarBajaEmpleadoAutorizado>((ref) {
  return ({
    required String empleadoId,
    required DateTime fechaBaja,
    required MotivoBajaEmpleado motivo,
    String? observaciones,
    required List<ResolucionResguardo> resoluciones,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'personal.archivar',
      () => ref.read(conciliarBajaEmpleadoUseCaseProvider).ejecutar(
            empleadoId: empleadoId,
            fechaBaja: fechaBaja,
            motivo: motivo,
            observaciones: observaciones,
            resoluciones: resoluciones,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      ConciliarBajaEmpleadoErrorInesperado.new,
    );
  };
});

/// Empleados ADMINISTRATIVOS y ACTIVOS — la única fuente válida para
/// autorizador y receptor (§9/§14). Devuelve el empleado con su puesto
/// resuelto, para mostrar "Juan Cruz — Operaciones".
final personalAdministrativoActivoProvider = FutureProvider<List<({EmpleadoData empleado, String? puesto})>>((ref) async {
  final repo = ref.watch(empleadoRepositoryProvider);
  final activos = await repo.listar(estatus: 'activo');
  final resultado = <({EmpleadoData empleado, String? puesto})>[];
  for (final empleado in activos) {
    final clasificacion = await repo.clasificar(empleado.id);
    if (clasificacion?.esAdministrativo ?? false) {
      resultado.add((empleado: empleado, puesto: clasificacion?.plantilla?.name));
    }
  }
  return resultado;
});
