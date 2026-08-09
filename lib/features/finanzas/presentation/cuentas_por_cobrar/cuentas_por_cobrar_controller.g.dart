// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cuentas_por_cobrar_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$cuentasPorCobrarControllerHash() =>
    r'5df952035b5cf4733fb382f2f692206eacdedd7b';

/// Controlador del listado de Cuentas por cobrar (Etapa 4J.1) — mismo
/// diseño que `AgendaController`. "Solo vencidas" se filtra en memoria
/// sobre la página cargada: `estaVencida` es derivada (Resolución D de
/// Marlon), no una columna que el repositorio pueda filtrar por SQL.
///
/// Copied from [CuentasPorCobrarController].
@ProviderFor(CuentasPorCobrarController)
final cuentasPorCobrarControllerProvider = AutoDisposeNotifierProvider<
  CuentasPorCobrarController,
  CuentasPorCobrarState
>.internal(
  CuentasPorCobrarController.new,
  name: r'cuentasPorCobrarControllerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$cuentasPorCobrarControllerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$CuentasPorCobrarController =
    AutoDisposeNotifier<CuentasPorCobrarState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
