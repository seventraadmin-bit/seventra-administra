import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/permissions/authorization_service.dart';
import '../organizacion/organizacion_providers.dart';
import '../usuarios/presentation/sesion_controller.dart';
import '../usuarios/usuarios_providers.dart';
import 'data/pdf/ficha_tecnica_pdf_renderer.dart';
import 'data/tables/empleado_table.dart';
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
  int? sueldoMensualAsignacion,
  int? bonoMensualAsignacion,
  String? sucursalId,
  String? bancoId,
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
    int? sueldoMensualAsignacion,
    int? bonoMensualAsignacion,
    String? sucursalId,
    String? bancoId,
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
            sueldoMensualAsignacion: sueldoMensualAsignacion,
            bonoMensualAsignacion: bonoMensualAsignacion,
            sucursalId: sucursalId,
            bancoId: bancoId,
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
      'personal.modificar',
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
      'personal.modificar',
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

final generarFichaTecnicaEmpleadoAutorizadoProvider = Provider<GenerarFichaTecnicaEmpleadoAutorizado>((ref) {
  return ({
    required String empleadoId,
    Set<String> seccionesExcluidas = const {},
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'personal.crear',
      () => ref.read(generarFichaTecnicaEmpleadoUseCaseProvider).ejecutar(
            empleadoId: empleadoId,
            seccionesExcluidas: seccionesExcluidas,
          ),
      GenerarFichaTecnicaEmpleadoErrorInesperado.new,
    );
  };
});
