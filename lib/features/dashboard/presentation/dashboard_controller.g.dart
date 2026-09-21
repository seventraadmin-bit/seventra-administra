// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dashboard_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$dashboardControllerHash() =>
    r'5fa2f7517b40433797bb920d2d01aa48d222d90b';

/// Controlador del Dashboard (Etapa 13, rediseño gerencial Etapa 15) —
/// pantalla inicial dinámica por permisos. Cada bloque verifica su
/// propio `hasCode('xxx.ver')` **antes** de invocar el use case
/// correspondiente; si falta el permiso, ese use case nunca se ejecuta
/// (mismo patrón que cada controller de Reportes, nunca "se consulta y
/// se oculta después").
///
/// Reutiliza directamente los 6 use cases de Reportes 12A–12D
/// (`obtenerResumenGeneralUseCaseProvider` y análogos) — nunca
/// redefine una consulta que Reportes ya resuelve. Los nuevos bloques
/// (cobertura, cobranza, próxima Nómina, personal operativo) componen
/// repositorios/use cases ya existentes — ver el doc comment de cada
/// uno en `domain/usecases/`.
///
/// [PeriodoDashboard] es la única fuente de verdad del rango
/// seleccionado (Parte B) — `cambiarPeriodo` es la única forma de
/// modificarlo, siempre desde la cabecera.
///
/// Copied from [DashboardController].
@ProviderFor(DashboardController)
final dashboardControllerProvider =
    AutoDisposeNotifierProvider<DashboardController, DashboardState>.internal(
      DashboardController.new,
      name: r'dashboardControllerProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$dashboardControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$DashboardController = AutoDisposeNotifier<DashboardState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
