// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sesion_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$sesionControllerHash() => r'779cdd9fd91c8723bf3240b02c50e845fce2d68c';

/// Sesión activa de RISEG ONE (Etapa 11A) — `null` significa "sin
/// sesión", el estado que fuerza al `redirect` del router a mandar a
/// `/login`. No se persiste entre reinicios a propósito (ver el plan de
/// la Etapa 11, §5): cada arranque de la aplicación exige iniciar
/// sesión de nuevo, nunca se guarda contraseña ni token.
///
/// Copied from [SesionController].
@ProviderFor(SesionController)
final sesionControllerProvider =
    AutoDisposeNotifierProvider<SesionController, SesionUsuario?>.internal(
      SesionController.new,
      name: r'sesionControllerProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$sesionControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$SesionController = AutoDisposeNotifier<SesionUsuario?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
