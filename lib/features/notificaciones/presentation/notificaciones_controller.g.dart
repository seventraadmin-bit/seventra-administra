// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notificaciones_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$notificacionesControllerHash() =>
    r'3514272ffbc8d37cfee08986199669cf5c3a4380';

/// Controlador del Centro de notificaciones (Etapa 14B) — mismo
/// principio de guardia real que Reportes/Dashboard/Búsqueda: cada
/// grupo se consulta solo si la sesión tiene su permiso, antes de
/// invocar `ObtenerNotificacionesUseCase`. Se carga al iniciar la
/// sesión y se vuelve a cargar cada vez que se abre la campana
/// (`recargar()`) — sin temporizadores ni tareas en segundo plano.
///
/// Copied from [NotificacionesController].
@ProviderFor(NotificacionesController)
final notificacionesControllerProvider = AutoDisposeNotifierProvider<
  NotificacionesController,
  NotificacionesState
>.internal(
  NotificacionesController.new,
  name: r'notificacionesControllerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$notificacionesControllerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$NotificacionesController = AutoDisposeNotifier<NotificacionesState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
