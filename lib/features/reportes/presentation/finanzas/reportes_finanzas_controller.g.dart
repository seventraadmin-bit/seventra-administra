// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reportes_finanzas_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$reportesFinanzasControllerHash() =>
    r'f298e5910967baa67962b075517a8d2836071338';

/// Controlador de la pestaña Finanzas de Reportes (Etapa 12A).
///
/// Guardia de permiso real (no solo la pestaña oculta en
/// `ReportesShellScreen`): si la sesión no tiene `finanzas.ver`, esta
/// función retorna sin ejecutar ninguna consulta — `state` se queda en
/// ceros/listas vacías y `sinAutorizacion == true` para que la pantalla
/// muestre un estado explícito, nunca datos parciales.
///
/// Copied from [ReportesFinanzasController].
@ProviderFor(ReportesFinanzasController)
final reportesFinanzasControllerProvider = AutoDisposeNotifierProvider<
  ReportesFinanzasController,
  ReportesFinanzasState
>.internal(
  ReportesFinanzasController.new,
  name: r'reportesFinanzasControllerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$reportesFinanzasControllerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$ReportesFinanzasController =
    AutoDisposeNotifier<ReportesFinanzasState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
