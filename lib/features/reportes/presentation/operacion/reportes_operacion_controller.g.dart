// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reportes_operacion_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$reportesOperacionControllerHash() =>
    r'66c01691e36a8759d435b8742e8fdcbcee385d7b';

/// Controlador de la pestaña Operación de Reportes (Etapa 12C).
///
/// Cada bloque (Compras/Inventario/Vehículos/Telefonía) verifica su
/// propio permiso **antes** de llamar a su caso de uso — mismo patrón
/// que `ReportesPersonalNominaController` (Etapa 12B), extendido de 2 a
/// 4 subsecciones independientes.
///
/// Copied from [ReportesOperacionController].
@ProviderFor(ReportesOperacionController)
final reportesOperacionControllerProvider = AutoDisposeNotifierProvider<
  ReportesOperacionController,
  ReportesOperacionState
>.internal(
  ReportesOperacionController.new,
  name: r'reportesOperacionControllerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$reportesOperacionControllerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$ReportesOperacionController =
    AutoDisposeNotifier<ReportesOperacionState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
