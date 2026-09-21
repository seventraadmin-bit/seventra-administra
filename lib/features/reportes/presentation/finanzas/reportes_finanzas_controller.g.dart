// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reportes_finanzas_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$reportesFinanzasControllerHash() =>
    r'33d34d13e2aa77ea2d33feb8249487b059e6c896';

/// Controlador de la pestaña Finanzas de Reportes.
///
/// Guardia de permiso real (no solo la pestaña oculta en
/// `ReportesShellScreen`): si la sesión no tiene `finanzas.ver`, esta
/// función retorna sin ejecutar ninguna consulta — `state` se queda en
/// ceros/listas vacías y `sinAutorizacion == true` para que la pantalla
/// muestre un estado explícito, nunca datos parciales.
///
/// Dos universos temporales distintos conviven aquí y la pantalla los
/// distingue siempre: el **periodo** (operativo, pagos, movimientos de
/// deuda) y la **fecha de hoy** (cartera, saldos de deuda). Cambiar el
/// rango recalcula el primero; los segundos no dependen de él.
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
