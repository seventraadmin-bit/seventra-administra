// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reportes_patrimonio_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$reportesPatrimonioControllerHash() =>
    r'25e358bb5e826f59c8aa2d7d5d75c6272ac2ca97';

/// Controlador de la pestaña Patrimonio y bajas.
///
/// La guardia real vive aquí, no sólo en la pestaña oculta: el reporte
/// cruza personas con bienes, así que exige **ambos** permisos. Con uno
/// solo no se consulta nada y la pantalla lo dice — nunca media verdad.
///
/// Copied from [ReportesPatrimonioController].
@ProviderFor(ReportesPatrimonioController)
final reportesPatrimonioControllerProvider = AutoDisposeNotifierProvider<
  ReportesPatrimonioController,
  ReportesPatrimonioState
>.internal(
  ReportesPatrimonioController.new,
  name: r'reportesPatrimonioControllerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$reportesPatrimonioControllerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$ReportesPatrimonioController =
    AutoDisposeNotifier<ReportesPatrimonioState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
