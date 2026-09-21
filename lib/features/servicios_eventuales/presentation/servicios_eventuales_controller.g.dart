// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'servicios_eventuales_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$serviciosEventualesControllerHash() =>
    r'6f351041601a09999d6a231a29ce836bf89fd20d';

/// Controlador de Comercial → Eventuales.
///
/// Todas las escrituras pasan por las fachadas `*Autorizado`: la
/// pantalla nunca llama a un caso de uso directamente, así que ninguna
/// ruta de UI puede saltarse la facultad.
///
/// Sólo las operaciones que mueven dinero (pagar y revertir pago)
/// invalidan Finanzas — programar una cobertura no crea ningún Egreso
/// ni ningún cargo, y hacer que Egresos se recargue por eso sería
/// mentirle al usuario sobre lo que acaba de pasar.
///
/// Copied from [ServiciosEventualesController].
@ProviderFor(ServiciosEventualesController)
final serviciosEventualesControllerProvider = AutoDisposeNotifierProvider<
  ServiciosEventualesController,
  ServiciosEventualesState
>.internal(
  ServiciosEventualesController.new,
  name: r'serviciosEventualesControllerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$serviciosEventualesControllerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$ServiciosEventualesController =
    AutoDisposeNotifier<ServiciosEventualesState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
