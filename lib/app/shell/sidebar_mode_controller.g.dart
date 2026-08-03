// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sidebar_mode_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$sidebarModeControllerHash() =>
    r'8ff3c93794bd00e56f53d4e4a67ea244b201fde6';

/// Controla el [SidebarMode] elegido por el usuario en la sesión actual.
///
/// No se persiste entre reinicios (decisión deliberada de esta etapa):
/// siempre arranca en [SidebarMode.automatico].
///
/// Copied from [SidebarModeController].
@ProviderFor(SidebarModeController)
final sidebarModeControllerProvider =
    AutoDisposeNotifierProvider<SidebarModeController, SidebarMode>.internal(
      SidebarModeController.new,
      name: r'sidebarModeControllerProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$sidebarModeControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$SidebarModeController = AutoDisposeNotifier<SidebarMode>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
