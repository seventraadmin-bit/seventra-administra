// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'respaldo_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$respaldoControllerHash() =>
    r'468301a9b9eaa57432a11d61c969eb531c317226';

/// Controlador de la pantalla de Respaldo y restauración (exclusiva del
/// Usuario Maestro). Lista lo que existe en `AppPaths.backupsDir` y
/// delega crear/restaurar/verificar/eliminar a los providers
/// autorizados, que exigen Maestro con el mismo mecanismo que la
/// eliminación física — este controlador nunca decide por su cuenta si
/// la acción está permitida.
///
/// Copied from [RespaldoController].
@ProviderFor(RespaldoController)
final respaldoControllerProvider =
    AutoDisposeNotifierProvider<RespaldoController, RespaldoState>.internal(
      RespaldoController.new,
      name: r'respaldoControllerProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$respaldoControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$RespaldoController = AutoDisposeNotifier<RespaldoState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
