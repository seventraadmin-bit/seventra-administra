// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reportes_rango_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$reportesRangoControllerHash() =>
    r'4e11942823799d093fd0364b9167e0d9e871dd08';

/// Periodo compartido por las cuatro pestañas de Reportes.
///
/// `keepAlive` porque el rango tiene que **sobrevivir al cambio de
/// pestaña**: el comportamiento anterior —cada pestaña con su propio
/// rango, reiniciado al mes en curso— obligaba a recapturar las fechas
/// en cada pestaña y hacía imposible comparar General contra Finanzas
/// sobre el mismo periodo. Sin `keepAlive` el provider se destruiría al
/// desmontarse la pestaña y el rango volvería al default, que es
/// exactamente el defecto que se está corrigiendo.
///
/// Copied from [ReportesRangoController].
@ProviderFor(ReportesRangoController)
final reportesRangoControllerProvider =
    NotifierProvider<ReportesRangoController, SeleccionRangoReportes>.internal(
      ReportesRangoController.new,
      name: r'reportesRangoControllerProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$reportesRangoControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ReportesRangoController = Notifier<SeleccionRangoReportes>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
