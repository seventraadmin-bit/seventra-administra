// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'personal_activo_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$personalActivoControllerHash() =>
    r'6d16aedafe94a1fe808d30621e0c9bbebcda866a';

/// Controlador de "Personal activo" (Etapa 15, rediseño de
/// Personal/Bajas) — mismo diseño que `EmpleadosListController`, con
/// la Asignación de Servicio vigente resuelta en una sola consulta por
/// lote (`listarTodasActivas`, nunca N+1 por Empleado).
///
/// Copied from [PersonalActivoController].
@ProviderFor(PersonalActivoController)
final personalActivoControllerProvider = AutoDisposeNotifierProvider<
  PersonalActivoController,
  PersonalActivoState
>.internal(
  PersonalActivoController.new,
  name: r'personalActivoControllerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$personalActivoControllerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$PersonalActivoController = AutoDisposeNotifier<PersonalActivoState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
