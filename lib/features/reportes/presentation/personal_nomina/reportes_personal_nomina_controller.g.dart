// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reportes_personal_nomina_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$reportesPersonalNominaControllerHash() =>
    r'2fa908a436f31ec05d33863ff20a9e47f7d5fc31';

/// Controlador de la pestaña Personal · Nómina de Reportes (Etapa 12B).
///
/// Cada subsección verifica su propio permiso **antes** de llamar a su
/// caso de uso — un usuario con `personal.ver` sin `nomina.ver` nunca
/// dispara ninguna consulta de Nómina, y viceversa. Mismo patrón que
/// `ReportesFinanzasController` (Etapa 12A).
///
/// Copied from [ReportesPersonalNominaController].
@ProviderFor(ReportesPersonalNominaController)
final reportesPersonalNominaControllerProvider = AutoDisposeNotifierProvider<
  ReportesPersonalNominaController,
  ReportesPersonalNominaState
>.internal(
  ReportesPersonalNominaController.new,
  name: r'reportesPersonalNominaControllerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$reportesPersonalNominaControllerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$ReportesPersonalNominaController =
    AutoDisposeNotifier<ReportesPersonalNominaState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
