// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'telefonia_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$telefoniaControllerHash() =>
    r'9e1525269cff482009a8a3f79afe3f8333267c24';

/// Controlador de Telefonía (Etapa 9A) — listado de líneas + todas las
/// operaciones de expediente, mismo criterio que `VehiculosController`
/// (un solo controlador para listado + expediente).
///
/// Copied from [TelefoniaController].
@ProviderFor(TelefoniaController)
final telefoniaControllerProvider =
    AutoDisposeNotifierProvider<TelefoniaController, TelefoniaState>.internal(
      TelefoniaController.new,
      name: r'telefoniaControllerProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$telefoniaControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$TelefoniaController = AutoDisposeNotifier<TelefoniaState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
