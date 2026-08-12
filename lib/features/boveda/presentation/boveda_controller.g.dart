// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'boveda_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$bovedaControllerHash() => r'00316a540e3e6243914a3bcd8e773dc568d9d343';

/// Controlador de la pantalla de la Bóveda de Accesos del Maestro
/// (Etapa 14D) — mismo criterio que `AuditoriaController`: sin
/// autorización propia de lectura (la pantalla ya solo es alcanzable
/// con Maestro, ver `app_router.dart`); las acciones de escritura
/// (crear/editar/cambiar secreto/revelar/baja/reactivar) sí pasan
/// siempre por su `XxxAutorizadoProvider` (`exigirMaestro`).
///
/// Copied from [BovedaController].
@ProviderFor(BovedaController)
final bovedaControllerProvider =
    AutoDisposeNotifierProvider<BovedaController, BovedaState>.internal(
      BovedaController.new,
      name: r'bovedaControllerProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$bovedaControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$BovedaController = AutoDisposeNotifier<BovedaState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
