// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bajas_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$bajasControllerHash() => r'612423d4bee3d8c2d7b1d223bd04d2460c2b1467';

/// Controlador de "BAJAS DE PERSONAL" (Etapa 15) — carga TODOS los
/// Empleados + TODOS sus periodos archivados una sola vez y construye
/// los eventos con `construirEventosBaja`; periodo/filtros de tabla se
/// aplican después, en memoria (ver `BajasState`).
///
/// Copied from [BajasController].
@ProviderFor(BajasController)
final bajasControllerProvider =
    AutoDisposeNotifierProvider<BajasController, BajasState>.internal(
      BajasController.new,
      name: r'bajasControllerProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$bajasControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$BajasController = AutoDisposeNotifier<BajasState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
