// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cuentas_financieras_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$cuentasFinancierasControllerHash() =>
    r'bfa0b4efc0ed221162014e813fa5b520ae3ea643';

/// Controlador del listado de Cuentas financieras (Etapa 19C) — mismo
/// diseño que `DeudasCreditoController`. El saldo por cuenta se
/// resuelve en lote (`calcularSaldos`), nunca una consulta por fila.
///
/// Copied from [CuentasFinancierasController].
@ProviderFor(CuentasFinancierasController)
final cuentasFinancierasControllerProvider = AutoDisposeNotifierProvider<
  CuentasFinancierasController,
  CuentasFinancierasState
>.internal(
  CuentasFinancierasController.new,
  name: r'cuentasFinancierasControllerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$cuentasFinancierasControllerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$CuentasFinancierasController =
    AutoDisposeNotifier<CuentasFinancierasState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
