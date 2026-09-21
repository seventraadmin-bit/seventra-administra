// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reportes_general_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$reportesGeneralControllerHash() =>
    r'db13059c4a23365bec704567d90cc085928b94d5';

/// Controlador de la pestaña General de Reportes.
///
/// La guardia de permiso real vive **aquí** (punto de carga de datos),
/// no solo en `ReportesShellScreen` ocultando la pestaña — cada sección
/// del resumen solo se calcula si la sesión tiene el permiso del
/// dominio correspondiente (ver `ObtenerResumenGeneralUseCase`, que
/// deja cada campo en `null` cuando no se incluyó).
///
/// El rango se **observa** del controlador compartido: cambiarlo desde
/// la barra de filtro reconstruye este provider una sola vez y dispara
/// exactamente una carga, nunca una cascada de consultas por cada campo
/// del filtro.
///
/// Copied from [ReportesGeneralController].
@ProviderFor(ReportesGeneralController)
final reportesGeneralControllerProvider = AutoDisposeNotifierProvider<
  ReportesGeneralController,
  ReportesGeneralState
>.internal(
  ReportesGeneralController.new,
  name: r'reportesGeneralControllerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$reportesGeneralControllerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$ReportesGeneralController = AutoDisposeNotifier<ReportesGeneralState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
