// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'respaldo_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$respaldoControllerHash() =>
    r'33da4c0351a81d896e2b5c13ef03562aba5b9c26';

/// Controlador de la pantalla de Respaldo y restauración (Etapa 14C,
/// exclusiva del Usuario Maestro). Solo lista lo que ya existe en
/// `AppPaths.backupsDir` y delega crear/restaurar a los providers
/// autorizados (`crearRespaldoAutorizadoProvider`/
/// `restaurarAutorizadoProvider`, que exigen Maestro con el mismo
/// mecanismo que la eliminación física de la Etapa 11D) — este
/// controlador nunca decide por su cuenta si la acción está permitida.
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
