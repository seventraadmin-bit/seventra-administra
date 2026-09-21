// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'planeacion_financiera_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$planeacionFinancieraControllerHash() =>
    r'9a22eef202352aa56bd5d4dbf8184807114b3526';

/// Controlador de Planeación financiera (Etapa 19D) — consume
/// exactamente el mismo `ObtenerProyeccionCajaUseCase` que
/// `ResumenFinancieroController`, nunca una segunda lógica de
/// proyección. Lo único propio de esta pantalla es la serie diaria
/// (`calcularSerieDisponibilidad`, función pura) y el estado de
/// navegación del calendario (mes visible, día seleccionado).
///
/// Copied from [PlaneacionFinancieraController].
@ProviderFor(PlaneacionFinancieraController)
final planeacionFinancieraControllerProvider = AutoDisposeNotifierProvider<
  PlaneacionFinancieraController,
  PlaneacionFinancieraState
>.internal(
  PlaneacionFinancieraController.new,
  name: r'planeacionFinancieraControllerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$planeacionFinancieraControllerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$PlaneacionFinancieraController =
    AutoDisposeNotifier<PlaneacionFinancieraState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
