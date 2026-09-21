// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'resumen_financiero_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$resumenFinancieroControllerHash() =>
    r'20ef0ff783bc06d69987e2ae6c2a39a6c3bfe7cc';

/// Controlador de la portada ejecutiva de Finanzas (Etapa 17) —
/// compone use cases ya existentes de Finanzas/Reportes, nunca
/// duplica su lógica. Regla crítica (pedido §11): "Por cobrar"/
/// "Vencido" son saldos AL DÍA DE HOY, siempre sobre el universo
/// completo de Cuentas por cobrar — el periodo seleccionado nunca las
/// filtra, solo afecta Ingresos/Egresos/Flujo neto y los feeds.
///
/// Copied from [ResumenFinancieroController].
@ProviderFor(ResumenFinancieroController)
final resumenFinancieroControllerProvider = AutoDisposeNotifierProvider<
  ResumenFinancieroController,
  ResumenFinancieroState
>.internal(
  ResumenFinancieroController.new,
  name: r'resumenFinancieroControllerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$resumenFinancieroControllerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$ResumenFinancieroController =
    AutoDisposeNotifier<ResumenFinancieroState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
