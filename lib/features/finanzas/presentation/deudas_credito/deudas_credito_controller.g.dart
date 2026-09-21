// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'deudas_credito_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$deudasCreditoControllerHash() =>
    r'3e8d167a9c3e7a1535c42886dc0db50ac1377fbe';

/// Controlador del listado de Deudas y crédito (Etapa 19) — mismo
/// diseño que `CuentasPorCobrarController`. Los KPIs de la pantalla se
/// derivan en memoria sobre `state.deudas` (la página ya cargada,
/// filtrada), nunca una segunda consulta.
///
/// Copied from [DeudasCreditoController].
@ProviderFor(DeudasCreditoController)
final deudasCreditoControllerProvider = AutoDisposeNotifierProvider<
  DeudasCreditoController,
  DeudasCreditoState
>.internal(
  DeudasCreditoController.new,
  name: r'deudasCreditoControllerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$deudasCreditoControllerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$DeudasCreditoController = AutoDisposeNotifier<DeudasCreditoState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
