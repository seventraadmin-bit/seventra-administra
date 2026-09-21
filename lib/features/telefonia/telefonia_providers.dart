import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/security/credential_cipher.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';

import '../../core/di/providers.dart';
import '../../core/permissions/authorization_service.dart';
import '../organizacion/organizacion_providers.dart';
import '../personal/personal_providers.dart';
import '../usuarios/presentation/sesion_controller.dart';
import '../usuarios/usuarios_providers.dart';
import 'data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'data/repositories/equipo_telefonico_repository_impl.dart';
import 'data/repositories/linea_telefonica_equipo_repository_impl.dart';
import 'data/repositories/linea_telefonica_repository_impl.dart';
import 'data/repositories/recarga_linea_telefonica_repository_impl.dart';
import 'domain/repositories/asignacion_linea_telefonica_repository.dart';
import 'domain/repositories/equipo_telefonico_repository.dart';
import 'domain/repositories/linea_telefonica_equipo_repository.dart';
import 'domain/repositories/linea_telefonica_repository.dart';
import 'domain/repositories/recarga_linea_telefonica_repository.dart';
import 'domain/usecases/actualizar_correo_equipo_telefonico_usecase.dart';
import 'domain/usecases/adjuntar_comprobante_recarga_linea_telefonica_usecase.dart';
import 'domain/usecases/asignar_linea_telefonica_usecase.dart';
import 'domain/usecases/asociar_equipo_linea_telefonica_usecase.dart';
import 'domain/usecases/cambiar_asignacion_linea_telefonica_usecase.dart';
import 'domain/usecases/cambiar_contrasena_equipo_telefonico_usecase.dart';
import 'domain/usecases/cambiar_equipo_linea_telefonica_usecase.dart';
import 'domain/usecases/cambiar_estatus_linea_telefonica_usecase.dart';
import 'domain/usecases/configurar_equipo_telefonico_usecase.dart';
import 'domain/usecases/corregir_linea_telefonica_usecase.dart';
import 'domain/usecases/crear_linea_telefonica_usecase.dart';
import 'domain/usecases/dar_de_baja_linea_telefonica_usecase.dart';
import 'domain/usecases/eliminar_linea_telefonica_fisicamente_usecase.dart';
import 'domain/usecases/obtener_equipos_disponibles_linea_telefonica_usecase.dart';
import 'domain/usecases/obtener_historia_equipo_telefonico_usecase.dart';
import 'domain/usecases/obtener_opciones_asignacion_linea_telefonica_usecase.dart';
import 'domain/usecases/cancelar_recarga_linea_telefonica_usecase.dart';
import 'domain/usecases/corregir_recarga_linea_telefonica_usecase.dart';
import 'domain/usecases/registrar_recarga_linea_telefonica_usecase.dart';
import 'domain/usecases/retirar_asignacion_linea_telefonica_usecase.dart';
import 'domain/usecases/retirar_equipo_linea_telefonica_usecase.dart';
import 'domain/usecases/revelar_credencial_equipo_telefonico_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';

/// Providers del dominio Telefonía (Etapa 9A) — nace aquí, separado de
/// Inventario/Vehículos y del resto de dominios, mismo criterio que
/// cada dominio nuevo desde 4J.1.
///
/// `asignacionLineaTelefonicaRepositoryProvider` se declara antes que
/// `lineaTelefonicaRepositoryProvider`/`lineaTelefonicaEquipoRepositoryProvider`
/// porque ambos lo necesitan como dependencia (repositorio compone
/// repositorio, Etapa 9B).
final asignacionLineaTelefonicaRepositoryProvider = Provider<AsignacionLineaTelefonicaRepository>((ref) {
  return AsignacionLineaTelefonicaRepositoryImpl(ref.watch(appDatabaseProvider));
});

/// Lee la custodia real de Inventario (`AsignacionRepository`) — sólo
/// lee: desde la Rebanada 2 Telefonía no escribe custodia.
final lineaTelefonicaEquipoRepositoryProvider = Provider<LineaTelefonicaEquipoRepository>((ref) {
  return LineaTelefonicaEquipoRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(asignacionLineaTelefonicaRepositoryProvider),
    ref.watch(asignacionRepositoryProvider),
  );
});

final lineaTelefonicaRepositoryProvider = Provider<LineaTelefonicaRepository>((ref) {
  return LineaTelefonicaRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(asignacionLineaTelefonicaRepositoryProvider),
    ref.watch(lineaTelefonicaEquipoRepositoryProvider),
  );
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

/// Recargas (Etapa 9C) — operación prepago, sin planes/contratos.
final recargaLineaTelefonicaRepositoryProvider = Provider<RecargaLineaTelefonicaRepository>((ref) {
  return RecargaLineaTelefonicaRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(egresoRepositoryProvider),
    ref.watch(deudaRepositoryProvider),
    ref.watch(codigoSecuenciaServiceProvider),
  );
});

final corregirRecargaLineaTelefonicaUseCaseProvider =
    Provider<CorregirRecargaLineaTelefonicaUseCase>((ref) {
  return CorregirRecargaLineaTelefonicaUseCase(
    ref.watch(recargaLineaTelefonicaRepositoryProvider),
    ref.watch(lineaTelefonicaRepositoryProvider),
    ref.watch(deudaRepositoryProvider),
  );
});

final cancelarRecargaLineaTelefonicaUseCaseProvider =
    Provider<CancelarRecargaLineaTelefonicaUseCase>((ref) {
  return CancelarRecargaLineaTelefonicaUseCase(
    ref.watch(recargaLineaTelefonicaRepositoryProvider),
    ref.watch(lineaTelefonicaRepositoryProvider),
  );
});

final registrarRecargaLineaTelefonicaUseCaseProvider = Provider<RegistrarRecargaLineaTelefonicaUseCase>((ref) {
  return RegistrarRecargaLineaTelefonicaUseCase(
    ref.watch(recargaLineaTelefonicaRepositoryProvider),
    ref.watch(lineaTelefonicaRepositoryProvider),
    ref.watch(deudaRepositoryProvider),
  );
});

final adjuntarComprobanteRecargaLineaTelefonicaUseCaseProvider =
    Provider<AdjuntarComprobanteRecargaLineaTelefonicaUseCase>((ref) {
  return AdjuntarComprobanteRecargaLineaTelefonicaUseCase(
    ref.watch(recargaLineaTelefonicaRepositoryProvider),
    ref.watch(attachmentStorageProvider),
  );
});

/// Providers de Asignaciones y equipo asociado (Etapa 9B).
final asignarLineaTelefonicaUseCaseProvider = Provider<AsignarLineaTelefonicaUseCase>((ref) {
  return AsignarLineaTelefonicaUseCase(
    ref.watch(lineaTelefonicaRepositoryProvider),
    ref.watch(asignacionLineaTelefonicaRepositoryProvider),
    ref.watch(lineaTelefonicaEquipoRepositoryProvider),
  );
});

final cambiarAsignacionLineaTelefonicaUseCaseProvider = Provider<CambiarAsignacionLineaTelefonicaUseCase>((ref) {
  return CambiarAsignacionLineaTelefonicaUseCase(
    ref.watch(asignacionLineaTelefonicaRepositoryProvider),
    ref.watch(lineaTelefonicaEquipoRepositoryProvider),
    ref.watch(lineaTelefonicaRepositoryProvider),
  );
});

final retirarAsignacionLineaTelefonicaUseCaseProvider = Provider<RetirarAsignacionLineaTelefonicaUseCase>((ref) {
  return RetirarAsignacionLineaTelefonicaUseCase(
    ref.watch(asignacionLineaTelefonicaRepositoryProvider),
    ref.watch(lineaTelefonicaEquipoRepositoryProvider),
    ref.watch(lineaTelefonicaRepositoryProvider),
  );
});

final asociarEquipoLineaTelefonicaUseCaseProvider = Provider<AsociarEquipoLineaTelefonicaUseCase>((ref) {
  return AsociarEquipoLineaTelefonicaUseCase(
    ref.watch(lineaTelefonicaRepositoryProvider),
    ref.watch(lineaTelefonicaEquipoRepositoryProvider),
    ref.watch(inventarioRepositoryProvider),
    ref.watch(asignacionLineaTelefonicaRepositoryProvider),
  );
});

final cambiarEquipoLineaTelefonicaUseCaseProvider = Provider<CambiarEquipoLineaTelefonicaUseCase>((ref) {
  return CambiarEquipoLineaTelefonicaUseCase(
    ref.watch(lineaTelefonicaRepositoryProvider),
    ref.watch(lineaTelefonicaEquipoRepositoryProvider),
    ref.watch(inventarioRepositoryProvider),
    ref.watch(asignacionLineaTelefonicaRepositoryProvider),
  );
});

final retirarEquipoLineaTelefonicaUseCaseProvider = Provider<RetirarEquipoLineaTelefonicaUseCase>((ref) {
  return RetirarEquipoLineaTelefonicaUseCase(ref.watch(lineaTelefonicaEquipoRepositoryProvider));
});

/// Dependencia cruzada a `personal`/`organizacion`/`inventario`
/// (lectura) — mismo patrón ya establecido por
/// `ObtenerOpcionesAsignacionVehiculoUseCase`. La UI de Telefonía nunca
/// importa los repositorios de esos dominios directamente.
final obtenerOpcionesAsignacionLineaTelefonicaUseCaseProvider =
    Provider<ObtenerOpcionesAsignacionLineaTelefonicaUseCase>((ref) {
  return ObtenerOpcionesAsignacionLineaTelefonicaUseCase(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
  );
});

final obtenerEquiposDisponiblesLineaTelefonicaUseCaseProvider =
    Provider<ObtenerEquiposDisponiblesLineaTelefonicaUseCase>((ref) {
  return ObtenerEquiposDisponiblesLineaTelefonicaUseCase(
    ref.watch(inventarioRepositoryProvider),
    ref.watch(lineaTelefonicaEquipoRepositoryProvider),
  );
});

// --- Fachadas autorizadas (Etapa 11C) ---
//
// Asignaciones/equipo/recargas se operan desde diálogos que llaman
// directamente a estos casos de uso, sin pasar por `TelefoniaController`
// — mismo motivo que las fachadas de `personal_providers.dart`/
// `inventario_providers.dart`.
typedef AsignarLineaTelefonicaAutorizado = Future<AsignarLineaTelefonicaResultado> Function({
  required String lineaTelefonicaId,
  String? empleadoId,
  String? servicioId,
  required DateTime fechaInicio,
  String? observaciones,
  String? motivo,
});

final asignarLineaTelefonicaAutorizadoProvider = Provider<AsignarLineaTelefonicaAutorizado>((ref) {
  return ({
    required String lineaTelefonicaId,
    String? empleadoId,
    String? servicioId,
    required DateTime fechaInicio,
    String? observaciones,
    String? motivo,
  }) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'telefonia.crear',
      () => ref.read(asignarLineaTelefonicaUseCaseProvider).ejecutar(
            lineaTelefonicaId: lineaTelefonicaId,
            empleadoId: empleadoId,
            servicioId: servicioId,
            fechaInicio: fechaInicio,
            observaciones: observaciones,
            motivo: motivo,
            actorUsuarioId: actorUsuarioId,
          ),
      AsignarLineaTelefonicaErrorInesperado.new,
    );
  };
});

typedef CambiarAsignacionLineaTelefonicaAutorizado = Future<CambiarAsignacionLineaTelefonicaResultado> Function({
  required String asignacionLineaTelefonicaActualId,
  required DateTime fecha,
  String? observacionesTermino,
  String? nuevoEmpleadoId,
  String? nuevoServicioId,
  String? observacionesNueva,
  String? motivo,
});

final cambiarAsignacionLineaTelefonicaAutorizadoProvider = Provider<CambiarAsignacionLineaTelefonicaAutorizado>((ref) {
  return ({
    required String asignacionLineaTelefonicaActualId,
    required DateTime fecha,
    String? observacionesTermino,
    String? nuevoEmpleadoId,
    String? nuevoServicioId,
    String? observacionesNueva,
    String? motivo,
  }) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'telefonia.modificar',
      () => ref.read(cambiarAsignacionLineaTelefonicaUseCaseProvider).ejecutar(
            asignacionLineaTelefonicaActualId: asignacionLineaTelefonicaActualId,
            fecha: fecha,
            observacionesTermino: observacionesTermino,
            nuevoEmpleadoId: nuevoEmpleadoId,
            nuevoServicioId: nuevoServicioId,
            observacionesNueva: observacionesNueva,
            motivo: motivo,
            actorUsuarioId: actorUsuarioId,
          ),
      CambiarAsignacionLineaTelefonicaErrorInesperado.new,
    );
  };
});

typedef RetirarAsignacionLineaTelefonicaAutorizado = Future<RetirarAsignacionLineaTelefonicaResultado> Function({
  required String asignacionLineaTelefonicaId,
  required DateTime fechaTermino,
  String? observacionesTermino,
  String? motivo,
});

final retirarAsignacionLineaTelefonicaAutorizadoProvider = Provider<RetirarAsignacionLineaTelefonicaAutorizado>((ref) {
  return ({
    required String asignacionLineaTelefonicaId,
    required DateTime fechaTermino,
    String? observacionesTermino,
    String? motivo,
  }) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'telefonia.modificar',
      () => ref.read(retirarAsignacionLineaTelefonicaUseCaseProvider).ejecutar(
            asignacionLineaTelefonicaId: asignacionLineaTelefonicaId,
            fechaTermino: fechaTermino,
            observacionesTermino: observacionesTermino,
            motivo: motivo,
            actorUsuarioId: actorUsuarioId,
          ),
      RetirarAsignacionLineaTelefonicaErrorInesperado.new,
    );
  };
});

typedef AsociarEquipoLineaTelefonicaAutorizado = Future<AsociarEquipoLineaTelefonicaResultado> Function({
  required String lineaTelefonicaId,
  required String unidadId,
  required DateTime fechaInicio,
  String? observaciones,
  bool alinearLineaConCustodia,
});

final asociarEquipoLineaTelefonicaAutorizadoProvider = Provider<AsociarEquipoLineaTelefonicaAutorizado>((ref) {
  return ({
    required String lineaTelefonicaId,
    required String unidadId,
    required DateTime fechaInicio,
    String? observaciones,
    bool alinearLineaConCustodia = false,
  }) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'telefonia.modificar',
      () => ref.read(asociarEquipoLineaTelefonicaUseCaseProvider).ejecutar(
            lineaTelefonicaId: lineaTelefonicaId,
            unidadId: unidadId,
            fechaInicio: fechaInicio,
            observaciones: observaciones,
            alinearLineaConCustodia: alinearLineaConCustodia,
            actorUsuarioId: actorUsuarioId,
          ),
      AsociarEquipoLineaTelefonicaErrorInesperado.new,
    );
  };
});

typedef CambiarEquipoLineaTelefonicaAutorizado = Future<CambiarEquipoLineaTelefonicaResultado> Function({
  required String lineaTelefonicaId,
  required String nuevaUnidadId,
  required DateTime fecha,
  String? observaciones,
  bool alinearLineaConCustodia,
});

final cambiarEquipoLineaTelefonicaAutorizadoProvider = Provider<CambiarEquipoLineaTelefonicaAutorizado>((ref) {
  return ({
    required String lineaTelefonicaId,
    required String nuevaUnidadId,
    required DateTime fecha,
    String? observaciones,
    bool alinearLineaConCustodia = false,
  }) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'telefonia.modificar',
      () => ref.read(cambiarEquipoLineaTelefonicaUseCaseProvider).ejecutar(
            lineaTelefonicaId: lineaTelefonicaId,
            nuevaUnidadId: nuevaUnidadId,
            fecha: fecha,
            observaciones: observaciones,
            alinearLineaConCustodia: alinearLineaConCustodia,
            actorUsuarioId: actorUsuarioId,
          ),
      CambiarEquipoLineaTelefonicaErrorInesperado.new,
    );
  };
});

typedef RetirarEquipoLineaTelefonicaAutorizado = Future<RetirarEquipoLineaTelefonicaResultado> Function({
  required String lineaTelefonicaId,
  required DateTime fechaFin,
});

final retirarEquipoLineaTelefonicaAutorizadoProvider = Provider<RetirarEquipoLineaTelefonicaAutorizado>((ref) {
  return ({
    required String lineaTelefonicaId,
    required DateTime fechaFin,
  }) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'telefonia.modificar',
      () => ref.read(retirarEquipoLineaTelefonicaUseCaseProvider).ejecutar(
            lineaTelefonicaId: lineaTelefonicaId,
            fechaFin: fechaFin,
            actorUsuarioId: actorUsuarioId,
          ),
      RetirarEquipoLineaTelefonicaErrorInesperado.new,
    );
  };
});

typedef RegistrarRecargaLineaTelefonicaAutorizado = Future<RegistrarRecargaLineaTelefonicaResultado> Function({
  required String lineaTelefonicaId,
  required DateTime fecha,
  required int importe,
  required String formaPago,
  String? cuentaFinancieraId,
  String? deudaIdTarjeta,
  String? observaciones,
});

final registrarRecargaLineaTelefonicaAutorizadoProvider = Provider<RegistrarRecargaLineaTelefonicaAutorizado>((ref) {
  return ({
    required String lineaTelefonicaId,
    required DateTime fecha,
    required int importe,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
    String? observaciones,
  }) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'telefonia.recargar',
      () => ref.read(registrarRecargaLineaTelefonicaUseCaseProvider).ejecutar(
            lineaTelefonicaId: lineaTelefonicaId,
            fecha: fecha,
            importe: importe,
            formaPago: formaPago,
            cuentaFinancieraId: cuentaFinancieraId,
            deudaIdTarjeta: deudaIdTarjeta,
            observaciones: observaciones,
            actorUsuarioId: actorUsuarioId,
          ),
      RegistrarRecargaLineaTelefonicaErrorInesperado.new,
    );
  };
});

/// Corregir y anular una recarga (schemaVersion 81).
///
/// Ambas van bajo `telefonia.recargar`, el MISMO código que registrarla,
/// y no bajo uno nuevo. Auditado antes de decidirlo: a diferencia de
/// anular un mantenimiento de Vehículo —que revierte un Egreso real de
/// banco o libera un cargo de TDC— anular una recarga **no mueve
/// dinero**: Telefonía no genera Egreso (decisión deliberada desde la
/// Etapa 9C). Separar aquí un `telefonia.cancelar` daría la apariencia
/// de un control financiero que no existe, y quien puede registrar la
/// recarga es exactamente quien conoce si ocurrió o no.
typedef CorregirRecargaLineaTelefonicaAutorizado = Future<CorregirRecargaLineaTelefonicaResultado> Function({
  required String recargaLineaTelefonicaId,
  DateTime? fecha,
  int? importe,
  required String formaPago,
  String? cuentaFinancieraId,
  String? deudaIdTarjeta,
  String? observaciones,
  bool limpiarObservaciones,
  required String motivo,
});

final corregirRecargaLineaTelefonicaAutorizadoProvider =
    Provider<CorregirRecargaLineaTelefonicaAutorizado>((ref) {
  return ({
    required String recargaLineaTelefonicaId,
    DateTime? fecha,
    int? importe,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
    String? observaciones,
    bool limpiarObservaciones = false,
    required String motivo,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'telefonia.recargar',
      () => ref.read(corregirRecargaLineaTelefonicaUseCaseProvider).ejecutar(
            recargaLineaTelefonicaId: recargaLineaTelefonicaId,
            fecha: fecha,
            importe: importe,
            formaPago: formaPago,
            cuentaFinancieraId: cuentaFinancieraId,
            deudaIdTarjeta: deudaIdTarjeta,
            observaciones: observaciones,
            limpiarObservaciones: limpiarObservaciones,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CorregirRecargaLineaTelefonicaErrorInesperado.new,
    );
  };
});

typedef CancelarRecargaLineaTelefonicaAutorizado = Future<CancelarRecargaLineaTelefonicaResultado> Function({
  required String recargaLineaTelefonicaId,
  required String motivo,
});

final cancelarRecargaLineaTelefonicaAutorizadoProvider =
    Provider<CancelarRecargaLineaTelefonicaAutorizado>((ref) {
  return ({required String recargaLineaTelefonicaId, required String motivo}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'telefonia.recargar',
      () => ref.read(cancelarRecargaLineaTelefonicaUseCaseProvider).ejecutar(
            recargaLineaTelefonicaId: recargaLineaTelefonicaId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CancelarRecargaLineaTelefonicaErrorInesperado.new,
    );
  };
});

// Etapa 0 (auditoría de consistencia transversal — corrección de un
// hueco real de autorización): se invocaba desde el diálogo directo
// sobre el use case crudo, sin ningún `autorizarUseCase`. Mismo código
// que registrar la recarga.
typedef AdjuntarComprobanteRecargaLineaTelefonicaAutorizado = Future<AdjuntarComprobanteRecargaLineaTelefonicaResultado>
    Function({
  required String recargaLineaTelefonicaId,
  required String sourceFilePath,
  required String originalFileName,
  required String mimeType,
});

final adjuntarComprobanteRecargaLineaTelefonicaAutorizadoProvider =
    Provider<AdjuntarComprobanteRecargaLineaTelefonicaAutorizado>((ref) {
  return ({
    required String recargaLineaTelefonicaId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'telefonia.recargar',
      () => ref.read(adjuntarComprobanteRecargaLineaTelefonicaUseCaseProvider).ejecutar(
            recargaLineaTelefonicaId: recargaLineaTelefonicaId,
            sourceFilePath: sourceFilePath,
            originalFileName: originalFileName,
            mimeType: mimeType,
          ),
      AdjuntarComprobanteRecargaLineaTelefonicaErrorInesperado.new,
    );
  };
});

// --- Eliminación física extraordinaria (Etapa 11D) ---
//
// Facultad exclusiva del Usuario Maestro — `exigirMaestro` nunca
// consulta `PermisoUsuario`/`AuthorizationService.verificar`, así que
// ningún permiso dinámico puede otorgarla. El actor se resuelve aquí
// mismo, dentro del cierre — el diálogo nunca lo provee (mismo
// criterio que la resolución del permiso).
final eliminarLineaTelefonicaFisicamenteUseCaseProvider = Provider<EliminarLineaTelefonicaFisicamenteUseCase>((ref) {
  return EliminarLineaTelefonicaFisicamenteUseCase(ref.watch(lineaTelefonicaRepositoryProvider));
});

typedef EliminarLineaTelefonicaFisicamenteAutorizado = Future<EliminarLineaTelefonicaFisicamenteResultado> Function({
  required String lineaTelefonicaId,
  required String motivo,
});

final eliminarLineaTelefonicaFisicamenteAutorizadoProvider =
    Provider<EliminarLineaTelefonicaFisicamenteAutorizado>((ref) {
  return ({required String lineaTelefonicaId, required String motivo}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(eliminarLineaTelefonicaFisicamenteUseCaseProvider).ejecutar(
            lineaTelefonicaId: lineaTelefonicaId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      EliminarLineaTelefonicaFisicamenteErrorInesperado.new,
    );
  };
});

// --- Equipos telefónicos (Etapa 9D) ---
//
// "Equipo" nunca es una tabla nueva de identidad — se ensambla desde
// ArticuloUnidad/ArticuloUnidadTelefono (Inventario) +
// LineaTelefonicaEquipo/Asignacion (ya arriba). Lo único nuevo que se
// persiste aquí es la credencial cifrada y su bitácora.

final credentialCipherProvider = Provider<CredentialCipher>((ref) => CredentialCipher());

final equipoTelefonicoRepositoryProvider = Provider<EquipoTelefonicoRepository>((ref) {
  return EquipoTelefonicoRepositoryImpl(ref.watch(appDatabaseProvider));
});

final configurarEquipoTelefonicoUseCaseProvider = Provider<ConfigurarEquipoTelefonicoUseCase>((ref) {
  return ConfigurarEquipoTelefonicoUseCase(
    ref.watch(inventarioRepositoryProvider),
    ref.watch(articuloRepositoryProvider),
    ref.watch(equipoTelefonicoRepositoryProvider),
  );
});

typedef ConfigurarEquipoTelefonicoAutorizado = Future<ConfigurarEquipoTelefonicoResultado> Function({
  required String unidadId,
  required String imei,
  String? imei2,
});

final configurarEquipoTelefonicoAutorizadoProvider = Provider<ConfigurarEquipoTelefonicoAutorizado>((ref) {
  return ({required String unidadId, required String imei, String? imei2}) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'telefonia.modificar',
      () => ref.read(configurarEquipoTelefonicoUseCaseProvider).ejecutar(
            unidadId: unidadId,
            imei: imei,
            imei2: imei2,
            actorUsuarioId: actorUsuarioId,
          ),
      ConfigurarEquipoTelefonicoErrorInesperado.new,
    );
  };
});

final actualizarCorreoEquipoTelefonicoUseCaseProvider = Provider<ActualizarCorreoEquipoTelefonicoUseCase>((ref) {
  return ActualizarCorreoEquipoTelefonicoUseCase(
    ref.watch(inventarioRepositoryProvider),
    ref.watch(equipoTelefonicoRepositoryProvider),
  );
});

typedef ActualizarCorreoEquipoTelefonicoAutorizado = Future<ActualizarCorreoEquipoTelefonicoResultado> Function({
  required String unidadId,
  String? correo,
  String? observaciones,
});

final actualizarCorreoEquipoTelefonicoAutorizadoProvider =
    Provider<ActualizarCorreoEquipoTelefonicoAutorizado>((ref) {
  return ({required String unidadId, String? correo, String? observaciones}) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'telefonia.modificar',
      () => ref.read(actualizarCorreoEquipoTelefonicoUseCaseProvider).ejecutar(
            unidadId: unidadId,
            correo: correo,
            observaciones: observaciones,
            actorUsuarioId: actorUsuarioId,
          ),
      ActualizarCorreoEquipoTelefonicoErrorInesperado.new,
    );
  };
});

final cambiarContrasenaEquipoTelefonicoUseCaseProvider = Provider<CambiarContrasenaEquipoTelefonicoUseCase>((ref) {
  return CambiarContrasenaEquipoTelefonicoUseCase(
    ref.watch(inventarioRepositoryProvider),
    ref.watch(equipoTelefonicoRepositoryProvider),
    ref.watch(credentialCipherProvider),
  );
});

typedef CambiarContrasenaEquipoTelefonicoAutorizado = Future<CambiarContrasenaEquipoTelefonicoResultado> Function({
  required String unidadId,
  required String contrasena,
});

final cambiarContrasenaEquipoTelefonicoAutorizadoProvider =
    Provider<CambiarContrasenaEquipoTelefonicoAutorizado>((ref) {
  return ({required String unidadId, required String contrasena}) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'telefonia.modificar',
      () => ref.read(cambiarContrasenaEquipoTelefonicoUseCaseProvider).ejecutar(
            unidadId: unidadId,
            contrasena: contrasena,
            actorUsuarioId: actorUsuarioId,
          ),
      CambiarContrasenaEquipoTelefonicoErrorInesperado.new,
    );
  };
});

final revelarCredencialEquipoTelefonicoUseCaseProvider = Provider<RevelarCredencialEquipoTelefonicoUseCase>((ref) {
  return RevelarCredencialEquipoTelefonicoUseCase(
    ref.watch(inventarioRepositoryProvider),
    ref.watch(equipoTelefonicoRepositoryProvider),
    ref.watch(credentialCipherProvider),
  );
});

typedef RevelarCredencialEquipoTelefonicoAutorizado = Future<RevelarCredencialEquipoTelefonicoResultado> Function({
  required String unidadId,
  required AccionRevelacionCredencial accion,
});

/// Gateado por `telefonia.verCredenciales` — nunca `telefonia.ver`
/// solo (punto 4 de la Etapa 9D: ver Telefonía no implica poder
/// revelar contraseñas). El Maestro pasa automáticamente por
/// construcción de `autorizarUseCase`/`PermissionService`, sin caso
/// especial.
final revelarCredencialEquipoTelefonicoAutorizadoProvider =
    Provider<RevelarCredencialEquipoTelefonicoAutorizado>((ref) {
  return ({required String unidadId, required AccionRevelacionCredencial accion}) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'telefonia.verCredenciales',
      () => ref.read(revelarCredencialEquipoTelefonicoUseCaseProvider).ejecutar(
            unidadId: unidadId,
            accion: accion,
            actorUsuarioId: actorUsuarioId,
          ),
      RevelarCredencialEquipoTelefonicoErrorInesperado.new,
    );
  };
});

final obtenerHistoriaEquipoTelefonicoUseCaseProvider = Provider<ObtenerHistoriaEquipoTelefonicoUseCase>((ref) {
  return ObtenerHistoriaEquipoTelefonicoUseCase(
    ref.watch(inventarioRepositoryProvider),
    ref.watch(asignacionRepositoryProvider),
    ref.watch(lineaTelefonicaEquipoRepositoryProvider),
    ref.watch(lineaTelefonicaRepositoryProvider),
    ref.watch(recargaLineaTelefonicaRepositoryProvider),
    ref.watch(equipoTelefonicoRepositoryProvider),
  );
});
