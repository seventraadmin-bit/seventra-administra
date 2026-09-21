// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'areas_list_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$areasListControllerHash() =>
    r'5b30cab56bb9da505fac018a7c105fed69020735';

/// Controlador del listado de Áreas — carga, error, búsqueda y las
/// métricas reales de Puestos/Personal por Área. Las acciones (crear,
/// editar, activar, desactivar) se invocan directo desde la pantalla
/// vía sus propios casos de uso y luego llaman `recargar()`, mismo
/// patrón que `SucursalesListController`.
///
/// Copied from [AreasListController].
@ProviderFor(AreasListController)
final areasListControllerProvider =
    AutoDisposeNotifierProvider<AreasListController, AreasListState>.internal(
      AreasListController.new,
      name: r'areasListControllerProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$areasListControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$AreasListController = AutoDisposeNotifier<AreasListState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
