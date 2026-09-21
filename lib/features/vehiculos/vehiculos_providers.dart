import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/permissions/authorization_service.dart';
import '../organizacion/organizacion_providers.dart';
import '../personal/personal_providers.dart';
import '../usuarios/presentation/sesion_controller.dart';
import '../usuarios/usuarios_providers.dart';
import 'data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'data/repositories/vehiculo_documento_repository_impl.dart';
import 'data/repositories/vehiculo_kilometraje_repository_impl.dart';
import 'data/repositories/vehiculo_mantenimiento_repository_impl.dart';
import 'data/repositories/vehiculo_repository_impl.dart';
import 'domain/repositories/asignacion_vehiculo_repository.dart';
import 'domain/repositories/vehiculo_documento_repository.dart';
import 'domain/repositories/vehiculo_kilometraje_repository.dart';
import 'domain/repositories/vehiculo_mantenimiento_repository.dart';
import 'domain/repositories/vehiculo_repository.dart';
import '../finanzas/finanzas_providers.dart' show deudaRepositoryProvider;
import '../finanzas/domain/origen_financiero_gasto.dart';
import 'domain/usecases/cancelar_mantenimiento_vehiculo_usecase.dart';
import 'domain/usecases/corregir_documento_vehiculo_usecase.dart';
import 'domain/usecases/corregir_mantenimiento_vehiculo_usecase.dart';
import 'domain/usecases/actualizar_fotografia_vehiculo_usecase.dart';
import 'domain/usecases/adjuntar_archivo_documento_vehiculo_usecase.dart';
import 'domain/usecases/adjuntar_comprobante_mantenimiento_vehiculo_usecase.dart';
import 'domain/usecases/asignar_vehiculo_usecase.dart';
import 'domain/usecases/cambiar_asignacion_vehiculo_usecase.dart';
import 'domain/usecases/cambiar_estatus_vehiculo_usecase.dart';
import 'domain/usecases/corregir_vehiculo_usecase.dart';
import 'domain/usecases/crear_vehiculo_usecase.dart';
import 'domain/usecases/dar_de_baja_vehiculo_usecase.dart';
import 'domain/usecases/finalizar_mantenimiento_vehiculo_usecase.dart';
import 'domain/usecases/eliminar_vehiculo_fisicamente_usecase.dart';
import 'domain/usecases/obtener_alertas_vehiculos_usecase.dart';
import 'domain/usecases/obtener_opciones_asignacion_vehiculo_usecase.dart';
import 'domain/usecases/registrar_documento_vehiculo_usecase.dart';
import 'domain/usecases/registrar_kilometraje_vehiculo_usecase.dart';
import 'domain/usecases/registrar_mantenimiento_vehiculo_usecase.dart';
import 'domain/usecases/retirar_asignacion_vehiculo_usecase.dart';

/// Providers del dominio Vehículos (Etapa 8A) — nace aquí, separado de
/// Inventario y del resto de dominios, mismo criterio que cada dominio
/// nuevo desde 4J.1.
///
/// `asignacionVehiculoRepositoryProvider` se declara antes que
/// `vehiculoRepositoryProvider` porque este último lo necesita como
/// dependencia (repositorio compone repositorio, Etapa 8B — ver el doc
/// comment de `VehiculoRepositoryImpl`).
final asignacionVehiculoRepositoryProvider = Provider<AsignacionVehiculoRepository>((ref) {
  return AsignacionVehiculoRepositoryImpl(ref.watch(appDatabaseProvider));
});

final vehiculoRepositoryProvider = Provider<VehiculoRepository>((ref) {
  return VehiculoRepositoryImpl(ref.watch(appDatabaseProvider), ref.watch(asignacionVehiculoRepositoryProvider));
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

/// Providers de Asignaciones y kilometraje (Etapa 8B).
final vehiculoKilometrajeRepositoryProvider = Provider<VehiculoKilometrajeRepository>((ref) {
  return VehiculoKilometrajeRepositoryImpl(ref.watch(appDatabaseProvider));
});

final asignarVehiculoUseCaseProvider = Provider<AsignarVehiculoUseCase>((ref) {
  return AsignarVehiculoUseCase(
    ref.watch(vehiculoRepositoryProvider),
    ref.watch(asignacionVehiculoRepositoryProvider),
    ref.watch(vehiculoKilometrajeRepositoryProvider),
  );
});

final cambiarAsignacionVehiculoUseCaseProvider = Provider<CambiarAsignacionVehiculoUseCase>((ref) {
  return CambiarAsignacionVehiculoUseCase(ref.watch(asignacionVehiculoRepositoryProvider));
});

final retirarAsignacionVehiculoUseCaseProvider = Provider<RetirarAsignacionVehiculoUseCase>((ref) {
  return RetirarAsignacionVehiculoUseCase(
    ref.watch(asignacionVehiculoRepositoryProvider),
    ref.watch(vehiculoKilometrajeRepositoryProvider),
  );
});

final registrarKilometrajeVehiculoUseCaseProvider = Provider<RegistrarKilometrajeVehiculoUseCase>((ref) {
  return RegistrarKilometrajeVehiculoUseCase(
    ref.watch(vehiculoKilometrajeRepositoryProvider),
    ref.watch(vehiculoRepositoryProvider),
  );
});

/// Dependencia cruzada a `personal`/`organizacion` (lectura) — mismo
/// patrón ya establecido por
/// `obtenerEmpleadosResponsablesServicioUseCaseProvider` (Inventario).
/// La UI de Vehículos nunca importa `personal_providers.dart`/
/// `organizacion_providers.dart` directamente: solo conoce este caso
/// de uso.
final obtenerOpcionesAsignacionVehiculoUseCaseProvider = Provider<ObtenerOpcionesAsignacionVehiculoUseCase>((ref) {
  return ObtenerOpcionesAsignacionVehiculoUseCase(
    ref.watch(empleadoRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
  );
});

/// Providers de Documentos (Etapa 8C).
final vehiculoDocumentoRepositoryProvider = Provider<VehiculoDocumentoRepository>((ref) {
  return VehiculoDocumentoRepositoryImpl(ref.watch(appDatabaseProvider));
});

final registrarDocumentoVehiculoUseCaseProvider = Provider<RegistrarDocumentoVehiculoUseCase>((ref) {
  return RegistrarDocumentoVehiculoUseCase(
    ref.watch(vehiculoDocumentoRepositoryProvider),
    ref.watch(vehiculoRepositoryProvider),
  );
});

final corregirDocumentoVehiculoUseCaseProvider = Provider<CorregirDocumentoVehiculoUseCase>((ref) {
  return CorregirDocumentoVehiculoUseCase(
    ref.watch(vehiculoDocumentoRepositoryProvider),
    ref.watch(vehiculoRepositoryProvider),
  );
});

final adjuntarArchivoDocumentoVehiculoUseCaseProvider = Provider<AdjuntarArchivoDocumentoVehiculoUseCase>((ref) {
  return AdjuntarArchivoDocumentoVehiculoUseCase(
    ref.watch(vehiculoDocumentoRepositoryProvider),
    ref.watch(attachmentStorageProvider),
  );
});

/// Providers de Mantenimiento e incidencias (Etapa 8D).
final vehiculoMantenimientoRepositoryProvider = Provider<VehiculoMantenimientoRepository>((ref) {
  return VehiculoMantenimientoRepositoryImpl(ref.watch(appDatabaseProvider));
});

final registrarMantenimientoVehiculoUseCaseProvider = Provider<RegistrarMantenimientoVehiculoUseCase>((ref) {
  return RegistrarMantenimientoVehiculoUseCase(
    ref.watch(vehiculoMantenimientoRepositoryProvider),
    ref.watch(vehiculoRepositoryProvider),
    ref.watch(vehiculoKilometrajeRepositoryProvider),
    ref.watch(deudaRepositoryProvider),
  );
});

/// Ciclo completo del gasto de un mantenimiento (schemaVersion 80) —
/// corrección de cualquier transición de origen financiero y anulación
/// con reversión exacta.
final corregirMantenimientoVehiculoUseCaseProvider = Provider<CorregirMantenimientoVehiculoUseCase>((ref) {
  return CorregirMantenimientoVehiculoUseCase(
    ref.watch(vehiculoMantenimientoRepositoryProvider),
    ref.watch(vehiculoRepositoryProvider),
    ref.watch(deudaRepositoryProvider),
  );
});

final cancelarMantenimientoVehiculoUseCaseProvider = Provider<CancelarMantenimientoVehiculoUseCase>((ref) {
  return CancelarMantenimientoVehiculoUseCase(
    ref.watch(vehiculoMantenimientoRepositoryProvider),
    ref.watch(vehiculoRepositoryProvider),
  );
});

final adjuntarComprobanteMantenimientoVehiculoUseCaseProvider =
    Provider<AdjuntarComprobanteMantenimientoVehiculoUseCase>((ref) {
  return AdjuntarComprobanteMantenimientoVehiculoUseCase(
    ref.watch(vehiculoMantenimientoRepositoryProvider),
    ref.watch(attachmentStorageProvider),
  );
});

final finalizarMantenimientoVehiculoUseCaseProvider = Provider<FinalizarMantenimientoVehiculoUseCase>((ref) {
  return FinalizarMantenimientoVehiculoUseCase(
    ref.watch(vehiculoRepositoryProvider),
    ref.watch(asignacionVehiculoRepositoryProvider),
  );
});

/// Compartido por `AlertasVehiculosScreen` y el bloque de Vehículos en
/// Reportes generales (Etapa 12C) — misma orquestación, un solo lugar.
final obtenerAlertasVehiculosUseCaseProvider = Provider<ObtenerAlertasVehiculosUseCase>((ref) {
  return ObtenerAlertasVehiculosUseCase(
    ref.watch(vehiculoRepositoryProvider),
    ref.watch(vehiculoDocumentoRepositoryProvider),
    ref.watch(vehiculoMantenimientoRepositoryProvider),
    ref.watch(vehiculoKilometrajeRepositoryProvider),
  );
});

// --- Fachadas autorizadas (Etapa 11C) ---
//
// `registrar_documento_vehiculo_dialog.dart`/
// `registrar_mantenimiento_vehiculo_dialog.dart` llaman estos casos de
// uso directo, sin pasar por `VehiculosController` — mismo motivo que
// las fachadas de `personal_providers.dart`/`inventario_providers.dart`.
typedef RegistrarDocumentoVehiculoAutorizado = Future<RegistrarDocumentoVehiculoResultado> Function({
  required String vehiculoId,
  required String tipo,
  String? tipoOtroDescripcion,
  String? numeroFolio,
  DateTime? fechaEmision,
  DateTime? fechaVencimiento,
  String? observaciones,
});

final registrarDocumentoVehiculoAutorizadoProvider = Provider<RegistrarDocumentoVehiculoAutorizado>((ref) {
  return ({
    required String vehiculoId,
    required String tipo,
    String? tipoOtroDescripcion,
    String? numeroFolio,
    DateTime? fechaEmision,
    DateTime? fechaVencimiento,
    String? observaciones,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'vehiculos.operar',
      () => ref.read(registrarDocumentoVehiculoUseCaseProvider).ejecutar(
            vehiculoId: vehiculoId,
            tipo: tipo,
            tipoOtroDescripcion: tipoOtroDescripcion,
            numeroFolio: numeroFolio,
            fechaEmision: fechaEmision,
            fechaVencimiento: fechaVencimiento,
            observaciones: observaciones,
          ),
      RegistrarDocumentoVehiculoErrorInesperado.new,
    );
  };
});

typedef RegistrarMantenimientoVehiculoAutorizado = Future<RegistrarMantenimientoVehiculoResultado> Function({
  required String vehiculoId,
  required DateTime fecha,
  int? kilometraje,
  required String tipo,
  required String descripcion,
  String? tallerProveedor,
  int? costo,
  DateTime? proximoMantenimientoFecha,
  int? proximoMantenimientoKilometraje,
  String? observaciones,
  OrigenFinancieroGasto? origen,
});

final registrarMantenimientoVehiculoAutorizadoProvider = Provider<RegistrarMantenimientoVehiculoAutorizado>((ref) {
  return ({
    required String vehiculoId,
    required DateTime fecha,
    int? kilometraje,
    required String tipo,
    required String descripcion,
    String? tallerProveedor,
    int? costo,
    DateTime? proximoMantenimientoFecha,
    int? proximoMantenimientoKilometraje,
    String? observaciones,
    OrigenFinancieroGasto? origen,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'vehiculos.operar',
      () => ref.read(registrarMantenimientoVehiculoUseCaseProvider).ejecutar(
            origen: origen,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
            vehiculoId: vehiculoId,
            fecha: fecha,
            kilometraje: kilometraje,
            tipo: tipo,
            descripcion: descripcion,
            tallerProveedor: tallerProveedor,
            costo: costo,
            proximoMantenimientoFecha: proximoMantenimientoFecha,
            proximoMantenimientoKilometraje: proximoMantenimientoKilometraje,
            observaciones: observaciones,
          ),
      RegistrarMantenimientoVehiculoErrorInesperado.new,
    );
  };
});

// Etapa 0 (auditoría de consistencia transversal — corrección de un
// hueco real de autorización): `registrar_documento_vehiculo_dialog.dart`/
// `registrar_mantenimiento_vehiculo_dialog.dart` adjuntaban el archivo
// llamando al caso de uso crudo, sin ningún `autorizarUseCase`. Mismo
// permiso que registrar el Documento/Mantenimiento al que pertenecen.
typedef AdjuntarArchivoDocumentoVehiculoAutorizado = Future<AdjuntarArchivoDocumentoVehiculoResultado> Function({
  required String vehiculoDocumentoId,
  required String sourceFilePath,
  required String originalFileName,
  required String mimeType,
});

final adjuntarArchivoDocumentoVehiculoAutorizadoProvider = Provider<AdjuntarArchivoDocumentoVehiculoAutorizado>((ref) {
  return ({
    required String vehiculoDocumentoId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'vehiculos.operar',
      () => ref.read(adjuntarArchivoDocumentoVehiculoUseCaseProvider).ejecutar(
            vehiculoDocumentoId: vehiculoDocumentoId,
            sourceFilePath: sourceFilePath,
            originalFileName: originalFileName,
            mimeType: mimeType,
          ),
      AdjuntarArchivoDocumentoVehiculoErrorInesperado.new,
    );
  };
});

typedef AdjuntarComprobanteMantenimientoVehiculoAutorizado = Future<AdjuntarComprobanteMantenimientoVehiculoResultado>
    Function({
  required String vehiculoMantenimientoId,
  required String sourceFilePath,
  required String originalFileName,
  required String mimeType,
});

final adjuntarComprobanteMantenimientoVehiculoAutorizadoProvider =
    Provider<AdjuntarComprobanteMantenimientoVehiculoAutorizado>((ref) {
  return ({
    required String vehiculoMantenimientoId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'vehiculos.operar',
      () => ref.read(adjuntarComprobanteMantenimientoVehiculoUseCaseProvider).ejecutar(
            vehiculoMantenimientoId: vehiculoMantenimientoId,
            sourceFilePath: sourceFilePath,
            originalFileName: originalFileName,
            mimeType: mimeType,
          ),
      AdjuntarComprobanteMantenimientoVehiculoErrorInesperado.new,
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
final eliminarVehiculoFisicamenteUseCaseProvider = Provider<EliminarVehiculoFisicamenteUseCase>((ref) {
  return EliminarVehiculoFisicamenteUseCase(ref.watch(vehiculoRepositoryProvider));
});

typedef EliminarVehiculoFisicamenteAutorizado = Future<EliminarVehiculoFisicamenteResultado> Function({
  required String vehiculoId,
  required String motivo,
});

final eliminarVehiculoFisicamenteAutorizadoProvider = Provider<EliminarVehiculoFisicamenteAutorizado>((ref) {
  return ({required String vehiculoId, required String motivo}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(eliminarVehiculoFisicamenteUseCaseProvider).ejecutar(
            vehiculoId: vehiculoId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      EliminarVehiculoFisicamenteErrorInesperado.new,
    );
  };
});

/// Corregir un gasto de mantenimiento (schemaVersion 80).
///
/// Se gatea con `vehiculos.operar`, el mismo código que registrar el
/// mantenimiento: son operaciones sobre un registro operativo del
/// vehículo, no sobre el expediente (`vehiculos.modificar`). Una
/// corrección AJUSTA el importe (y su origen), nunca lo devuelve — por
/// eso vive con la operación ordinaria y no con la anulación.
typedef CorregirMantenimientoVehiculoAutorizado = Future<CorregirMantenimientoVehiculoResultado> Function({
  required String vehiculoMantenimientoId,
  DateTime? fecha,
  String? tipo,
  String? descripcion,
  String? tallerProveedor,
  int? costo,
  bool limpiarCosto,
  DateTime? proximoMantenimientoFecha,
  int? proximoMantenimientoKilometraje,
  String? observaciones,
  OrigenFinancieroGasto? origen,
  required String motivo,
});

final corregirMantenimientoVehiculoAutorizadoProvider =
    Provider<CorregirMantenimientoVehiculoAutorizado>((ref) {
  return ({
    required String vehiculoMantenimientoId,
    DateTime? fecha,
    String? tipo,
    String? descripcion,
    String? tallerProveedor,
    int? costo,
    bool limpiarCosto = false,
    DateTime? proximoMantenimientoFecha,
    int? proximoMantenimientoKilometraje,
    String? observaciones,
    OrigenFinancieroGasto? origen,
    required String motivo,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'vehiculos.operar',
      () => ref.read(corregirMantenimientoVehiculoUseCaseProvider).ejecutar(
            vehiculoMantenimientoId: vehiculoMantenimientoId,
            fecha: fecha,
            tipo: tipo,
            descripcion: descripcion,
            tallerProveedor: tallerProveedor,
            costo: costo,
            limpiarCosto: limpiarCosto,
            proximoMantenimientoFecha: proximoMantenimientoFecha,
            proximoMantenimientoKilometraje: proximoMantenimientoKilometraje,
            observaciones: observaciones,
            origen: origen,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CorregirMantenimientoVehiculoErrorInesperado.new,
    );
  };
});

typedef CancelarMantenimientoVehiculoAutorizado = Future<CancelarMantenimientoVehiculoResultado> Function({
  required String vehiculoMantenimientoId,
  required String motivo,
});

/// Anular un mantenimiento exige `vehiculos.cancelar`, **nunca**
/// `vehiculos.operar` (decisión de Marlon, schemaVersion 80).
///
/// Es la única acción de Vehículos que revierte dinero real: cancela el
/// `Egreso` de una `CuentaFinanciera`, o libera el cargo de una TDC con
/// un ajuste negativo. Quien captura la operación no necesariamente
/// puede revertirla — mismo criterio ya vigente en `compras.cancelar`,
/// `tiempoExtra.cancelar` y `nomina.cancelarPago`.
///
/// El código es exclusivo: `vehiculos.operar` **no** abre esta puerta, y
/// `vehiculos.cancelar` por sí solo no concede registrar ni corregir
/// nada, ni ningún acceso a Finanzas. El Maestro pasa siempre, por
/// `SessionPermissionService`, sin filas de `PermisoUsuario`.
///
/// La compuerta REAL está aquí, no en la UI: el menú del expediente
/// oculta "Anular" a quien no tenga el código, pero llamar este
/// provider directo (o desde una prueba con `ProviderContainer`) exige
/// exactamente lo mismo.
final cancelarMantenimientoVehiculoAutorizadoProvider =
    Provider<CancelarMantenimientoVehiculoAutorizado>((ref) {
  return ({required String vehiculoMantenimientoId, required String motivo}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'vehiculos.cancelar',
      () => ref.read(cancelarMantenimientoVehiculoUseCaseProvider).ejecutar(
            vehiculoMantenimientoId: vehiculoMantenimientoId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CancelarMantenimientoVehiculoErrorInesperado.new,
    );
  };
});

typedef CorregirDocumentoVehiculoAutorizado = Future<CorregirDocumentoVehiculoResultado> Function({
  required String vehiculoDocumentoId,
  String? tipo,
  String? tipoOtroDescripcion,
  String? numeroFolio,
  bool limpiarNumeroFolio,
  DateTime? fechaEmision,
  bool limpiarFechaEmision,
  DateTime? fechaVencimiento,
  bool limpiarFechaVencimiento,
  String? observaciones,
  bool limpiarObservaciones,
  required String motivo,
});

/// Gateado con `vehiculos.operar`, igual que registrar/renovar un
/// documento: quien puede crear la vigencia es quien puede arreglar su
/// captura. No se inventa un permiso nuevo aquí — si Marlon quiere
/// separar "corregir" de "registrar", esa granularidad es una decisión
/// de producto que se reporta, no que se toma sola.
final corregirDocumentoVehiculoAutorizadoProvider = Provider<CorregirDocumentoVehiculoAutorizado>((ref) {
  return ({
    required String vehiculoDocumentoId,
    String? tipo,
    String? tipoOtroDescripcion,
    String? numeroFolio,
    bool limpiarNumeroFolio = false,
    DateTime? fechaEmision,
    bool limpiarFechaEmision = false,
    DateTime? fechaVencimiento,
    bool limpiarFechaVencimiento = false,
    String? observaciones,
    bool limpiarObservaciones = false,
    required String motivo,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'vehiculos.operar',
      () => ref.read(corregirDocumentoVehiculoUseCaseProvider).ejecutar(
            vehiculoDocumentoId: vehiculoDocumentoId,
            tipo: tipo,
            tipoOtroDescripcion: tipoOtroDescripcion,
            numeroFolio: numeroFolio,
            limpiarNumeroFolio: limpiarNumeroFolio,
            fechaEmision: fechaEmision,
            limpiarFechaEmision: limpiarFechaEmision,
            fechaVencimiento: fechaVencimiento,
            limpiarFechaVencimiento: limpiarFechaVencimiento,
            observaciones: observaciones,
            limpiarObservaciones: limpiarObservaciones,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CorregirDocumentoVehiculoErrorInesperado.new,
    );
  };
});
