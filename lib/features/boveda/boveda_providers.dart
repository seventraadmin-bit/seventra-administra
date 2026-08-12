import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/permissions/authorization_service.dart';
import '../../core/security/credential_cipher.dart';
import '../usuarios/presentation/sesion_controller.dart';
import '../usuarios/usuarios_providers.dart';
import 'data/repositories/boveda_credencial_repository_impl.dart';
import 'domain/repositories/boveda_credencial_repository.dart';
import 'domain/usecases/actualizar_credencial_boveda_usecase.dart';
import 'domain/usecases/cambiar_secreto_credencial_boveda_usecase.dart';
import 'domain/usecases/crear_credencial_boveda_usecase.dart';
import 'domain/usecases/dar_de_baja_credencial_boveda_usecase.dart';
import 'domain/usecases/reactivar_credencial_boveda_usecase.dart';
import 'domain/usecases/revelar_secreto_credencial_boveda_usecase.dart';

/// Misma clase genérica ya usada por Telefonía (Etapa 9D,
/// `telefonia_providers.dart`) — cifrado reversible con la clave
/// maestra única del Almacén de Credenciales de Windows. Se declara
/// aquí (no se importa la de Telefonía) para no crear una dependencia
/// cruzada entre dos dominios que no se conocen entre sí; ambas
/// instancias resuelven la misma clave porque `AlmacenClaveSeguraWindows`
/// usa un nombre de clave fijo, no una por instancia.
final credentialCipherProvider = Provider<CredentialCipher>((ref) => CredentialCipher());

final bovedaCredencialRepositoryProvider = Provider<BovedaCredencialRepository>((ref) {
  return BovedaCredencialRepositoryImpl(ref.watch(appDatabaseProvider));
});

final crearCredencialBovedaUseCaseProvider = Provider<CrearCredencialBovedaUseCase>((ref) {
  return CrearCredencialBovedaUseCase(ref.watch(bovedaCredencialRepositoryProvider), ref.watch(credentialCipherProvider));
});

final actualizarCredencialBovedaUseCaseProvider = Provider<ActualizarCredencialBovedaUseCase>((ref) {
  return ActualizarCredencialBovedaUseCase(ref.watch(bovedaCredencialRepositoryProvider));
});

final cambiarSecretoCredencialBovedaUseCaseProvider = Provider<CambiarSecretoCredencialBovedaUseCase>((ref) {
  return CambiarSecretoCredencialBovedaUseCase(ref.watch(bovedaCredencialRepositoryProvider), ref.watch(credentialCipherProvider));
});

final revelarSecretoCredencialBovedaUseCaseProvider = Provider<RevelarSecretoCredencialBovedaUseCase>((ref) {
  return RevelarSecretoCredencialBovedaUseCase(ref.watch(bovedaCredencialRepositoryProvider), ref.watch(credentialCipherProvider));
});

final darDeBajaCredencialBovedaUseCaseProvider = Provider<DarDeBajaCredencialBovedaUseCase>((ref) {
  return DarDeBajaCredencialBovedaUseCase(ref.watch(bovedaCredencialRepositoryProvider));
});

final reactivarCredencialBovedaUseCaseProvider = Provider<ReactivarCredencialBovedaUseCase>((ref) {
  return ReactivarCredencialBovedaUseCase(ref.watch(bovedaCredencialRepositoryProvider));
});

// Fachadas Maestro-only (Etapa 14D) — mismo patrón que
// `respaldo_providers.dart` (Etapa 14C): cada acción se envuelve con
// `exigirMaestro`, nunca se llama el UseCase directo desde la UI. La
// Bóveda entera es estructuralmente Maestro-only, sin ningún permiso
// dinámico de `PermisoUsuario` que la otorgue.

typedef CrearCredencialBovedaAutorizado = Future<CrearCredencialBovedaResultado> Function({
  required String nombre,
  required String tipo,
  String? usuarioAcceso,
  String? correo,
  String? secreto,
  String? url,
  String? observaciones,
});

final crearCredencialBovedaAutorizadoProvider = Provider<CrearCredencialBovedaAutorizado>((ref) {
  return ({required nombre, required tipo, usuarioAcceso, correo, secreto, url, observaciones}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(crearCredencialBovedaUseCaseProvider).ejecutar(
            nombre: nombre,
            tipo: tipo,
            usuarioAcceso: usuarioAcceso,
            correo: correo,
            secreto: secreto,
            url: url,
            observaciones: observaciones,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CrearCredencialBovedaErrorInesperado.new,
    );
  };
});

typedef ActualizarCredencialBovedaAutorizado = Future<ActualizarCredencialBovedaResultado> Function({
  required String id,
  required String nombre,
  required String tipo,
  String? usuarioAcceso,
  String? correo,
  String? url,
  String? observaciones,
  bool limpiarUsuarioAcceso,
  bool limpiarCorreo,
  bool limpiarUrl,
  bool limpiarObservaciones,
});

final actualizarCredencialBovedaAutorizadoProvider = Provider<ActualizarCredencialBovedaAutorizado>((ref) {
  return ({
    required id,
    required nombre,
    required tipo,
    usuarioAcceso,
    correo,
    url,
    observaciones,
    limpiarUsuarioAcceso = false,
    limpiarCorreo = false,
    limpiarUrl = false,
    limpiarObservaciones = false,
  }) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(actualizarCredencialBovedaUseCaseProvider).ejecutar(
            id: id,
            nombre: nombre,
            tipo: tipo,
            usuarioAcceso: usuarioAcceso,
            correo: correo,
            url: url,
            observaciones: observaciones,
            limpiarUsuarioAcceso: limpiarUsuarioAcceso,
            limpiarCorreo: limpiarCorreo,
            limpiarUrl: limpiarUrl,
            limpiarObservaciones: limpiarObservaciones,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      ActualizarCredencialBovedaErrorInesperado.new,
    );
  };
});

typedef CambiarSecretoCredencialBovedaAutorizado = Future<CambiarSecretoCredencialBovedaResultado> Function({
  required String id,
  String? secreto,
});

final cambiarSecretoCredencialBovedaAutorizadoProvider = Provider<CambiarSecretoCredencialBovedaAutorizado>((ref) {
  return ({required id, secreto}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(cambiarSecretoCredencialBovedaUseCaseProvider).ejecutar(
            id: id,
            secreto: secreto,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CambiarSecretoCredencialBovedaErrorInesperado.new,
    );
  };
});

typedef RevelarSecretoCredencialBovedaAutorizado = Future<RevelarSecretoCredencialBovedaResultado> Function({
  required String credencialId,
  required AccionRevelacionSecreto accion,
});

final revelarSecretoCredencialBovedaAutorizadoProvider = Provider<RevelarSecretoCredencialBovedaAutorizado>((ref) {
  return ({required credencialId, required accion}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(revelarSecretoCredencialBovedaUseCaseProvider).ejecutar(
            credencialId: credencialId,
            accion: accion,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      RevelarSecretoCredencialBovedaErrorInesperado.new,
    );
  };
});

typedef DarDeBajaCredencialBovedaAutorizado = Future<DarDeBajaCredencialBovedaResultado> Function({required String id});

final darDeBajaCredencialBovedaAutorizadoProvider = Provider<DarDeBajaCredencialBovedaAutorizado>((ref) {
  return ({required id}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(darDeBajaCredencialBovedaUseCaseProvider).ejecutar(
            id: id,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      DarDeBajaCredencialBovedaErrorInesperado.new,
    );
  };
});

typedef ReactivarCredencialBovedaAutorizado = Future<ReactivarCredencialBovedaResultado> Function({required String id});

final reactivarCredencialBovedaAutorizadoProvider = Provider<ReactivarCredencialBovedaAutorizado>((ref) {
  return ({required id}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(reactivarCredencialBovedaUseCaseProvider).ejecutar(
            id: id,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      ReactivarCredencialBovedaErrorInesperado.new,
    );
  };
});

// Lectura de listado/historial: `BovedaController` llama al repositorio
// directo (`ref.read(bovedaCredencialRepositoryProvider)`), mismo
// criterio que `AuditoriaController` — sin `exigirMaestro` propio, la
// pantalla ya solo es alcanzable con Maestro (ver `app_router.dart`), y
// nunca se expone en ningún módulo cross-cutting (Búsqueda/Reportes/
// Dashboard/Notificaciones no la conocen).
