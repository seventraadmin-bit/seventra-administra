// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reportes_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$reportesControllerHash() =>
    r'716afae429e991afc8c55e8706c589837971746e';

/// Controlador de Reportes (Etapa 7D) — cada sección es una consulta
/// derivada de los repositorios ya existentes, recalculada al cargar;
/// nunca se guarda un total ni un resumen aparte ("cero tablas de
/// resumen o totales persistidos", instrucción explícita de Marlon).
///
/// El costo promedio se omite (`null`) para Artículos con
/// `manejaVariante`: un solo número no representa de forma consistente
/// costos que legítimamente pueden diferir por talla — mostrarlo ahí
/// sería inventar precisión que la fuente no tiene.
///
/// Copied from [ReportesController].
@ProviderFor(ReportesController)
final reportesControllerProvider =
    AutoDisposeNotifierProvider<ReportesController, ReportesState>.internal(
      ReportesController.new,
      name: r'reportesControllerProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$reportesControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ReportesController = AutoDisposeNotifier<ReportesState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
