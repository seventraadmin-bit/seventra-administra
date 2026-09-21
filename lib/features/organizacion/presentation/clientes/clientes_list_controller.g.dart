// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'clientes_list_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$clientesListControllerHash() =>
    r'6b149da231f4da0036c4bd1444afa74cfd60240e';

/// Controlador del listado de Clientes comerciales — mismo shape que
/// `PuestosListController`, más las métricas reales de Comercial
/// (Etapa 16): Servicios activos y Personal asignado por Cliente,
/// ambos agregados en memoria sobre listados completos ya cargados en
/// una sola consulta cada uno.
///
/// Copied from [ClientesListController].
@ProviderFor(ClientesListController)
final clientesListControllerProvider = AutoDisposeNotifierProvider<
  ClientesListController,
  ClientesListState
>.internal(
  ClientesListController.new,
  name: r'clientesListControllerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$clientesListControllerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$ClientesListController = AutoDisposeNotifier<ClientesListState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
