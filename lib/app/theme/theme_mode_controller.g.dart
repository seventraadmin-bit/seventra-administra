// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'theme_mode_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$themeModeControllerHash() =>
    r'8a9e7aed41c6e910f68f8354804a18b342295232';

/// Controla el `ThemeMode` activo (claro/oscuro/sistema) y lo persiste en
/// `shared_preferences` — deliberadamente separado de Drift, que se reserva
/// para datos de negocio.
///
/// Copied from [ThemeModeController].
@ProviderFor(ThemeModeController)
final themeModeControllerProvider =
    AutoDisposeNotifierProvider<ThemeModeController, ThemeMode>.internal(
      ThemeModeController.new,
      name: r'themeModeControllerProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$themeModeControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ThemeModeController = AutoDisposeNotifier<ThemeMode>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
